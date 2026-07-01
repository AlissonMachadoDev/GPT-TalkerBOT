defmodule GptTalkerbot.PromptSettings.GroupContextExtractor do
  require Logger

  alias GptTalkerbot.LLM
  alias GptTalkerbot.PromptSettings.GroupContext

  @system_prompt """
  Você é um assistente que mantém um resumo de contexto de conversas de grupo.
  Dado o contexto atual (pode estar vazio) e um lote de novas mensagens, atualize o contexto
  para capturar: tópicos discutidos, decisões tomadas, referências importantes e humor geral do grupo.
  Seja conciso — máximo 300 palavras. Responda APENAS com o contexto atualizado, sem explicações.
  """

  def extract_and_update(chat_id, messages) do
    current_context = GroupContext.get_context(chat_id)
    messages_text = format_messages(messages)

    user_content = """
    Contexto atual:
    #{if current_context == "", do: "(nenhum ainda)", else: current_context}

    Novas mensagens:
    #{messages_text}
    """

    ai_messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: user_content}
    ]

    case LLM.complete_text(ai_messages, temperature: 0.3, max_tokens: 400, reasoning_effort: "none") do
      {:ok, new_context} ->
        GroupContext.update_context(chat_id, String.trim(new_context))
        Logger.info("GroupContextExtractor: updated context for chat #{chat_id}")

      {:error, reason} ->
        Logger.warning("GroupContextExtractor: AI call failed: #{inspect(reason)}")
    end
  end

  defp format_messages(messages) do
    Enum.map_join(messages, "\n", fn m ->
      ts = NaiveDateTime.to_time(m.inserted_at) |> Time.to_string() |> String.slice(0, 5)
      "[#{ts}] #{m.sender_name}: #{m.content}"
    end)
  end
end
