defmodule GptTalkerbot.Memory.ContextJanitor do
  @moduledoc """
  Faxina por IA no histórico de conversa de um chat.

  Numera as mensagens recentes, pede a um modelo (OpenAI, temperatura
  baixa) para apontar as degeneradas — salada de tokens, texto corrompido
  por erro de geração — e apaga as condenadas do histórico e do buffer do
  grupo. Disparada pelo comando /faxina (só admin).
  """

  import Ecto.Query

  alias GptTalkerbot.{GroupMessageCache, LLM, Repo}
  alias GptTalkerbot.Memory.ConversationMessage

  @review_limit 50
  @snippet_length 300

  @instruction """
  Você é um inspetor de qualidade de histórico de chat. Abaixo há mensagens \
  numeradas de uma conversa. Aponte APENAS as degeneradas: salada de tokens, \
  mistura sem sentido de idiomas e símbolos, texto claramente corrompido por \
  erro de geração de IA. NÃO marque mensagens por serem informais, vulgares, \
  debochadas, com gírias ou erros de digitação — isso é conversa normal.
  Responda APENAS com JSON no formato {"lixo": [numeros]}. Se nenhuma for \
  lixo, responda {"lixo": []}.
  """

  @doc """
  Revisa as mensagens recentes do chat e apaga as degeneradas.
  Retorna {:ok, revisadas, apagadas} ou {:error, reason}.
  """
  def sweep(chat_id) do
    messages = recent_messages(chat_id)

    if messages == [] do
      {:ok, 0, 0}
    else
      with {:ok, positions} <- classify(messages) do
        condemned =
          messages
          |> Enum.with_index(1)
          |> Enum.filter(fn {_message, idx} -> idx in positions end)
          |> Enum.map(fn {message, _idx} -> message end)

        {:ok, length(messages), purge(chat_id, condemned)}
      end
    end
  end

  defp recent_messages(chat_id) do
    ConversationMessage
    |> where([m], m.chat_id == ^chat_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(@review_limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  defp classify(messages) do
    with {:ok, content} <-
           LLM.complete_text([%{role: "user", content: review_list(messages)}],
             prompt: @instruction,
             provider: :openai,
             temperature: 0.2,
             max_tokens: 300
           ) do
      parse_verdict(content, length(messages))
    end
  end

  @doc false
  def review_list(messages) do
    messages
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {message, idx} ->
      snippet =
        message.content
        |> String.replace("\n", " ")
        |> String.slice(0, @snippet_length)

      "#{idx}. [#{message.role}] #{snippet}"
    end)
  end

  @doc false
  def parse_verdict(content, message_count) do
    content
    |> strip_code_fences()
    |> Jason.decode()
    |> case do
      {:ok, %{"lixo" => positions}} when is_list(positions) ->
        {:ok,
         positions
         |> Enum.filter(&(is_integer(&1) and &1 >= 1 and &1 <= message_count))
         |> Enum.uniq()}

      _ ->
        {:error, :invalid_verdict}
    end
  end

  defp purge(_chat_id, []), do: 0

  defp purge(chat_id, condemned) do
    ids = Enum.map(condemned, & &1.id)

    {count, _} =
      ConversationMessage
      |> where([m], m.id in ^ids)
      |> Repo.delete_all()

    # O lixo do bot também entrou no buffer que alimenta /resumo e as
    # interjeições — sai de lá junto
    condemned
    |> Enum.map(& &1.content)
    |> Enum.uniq()
    |> Enum.each(&GroupMessageCache.forget(chat_id, &1))

    count
  end

  defp strip_code_fences(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/\s*```\z/, "")
  end
end
