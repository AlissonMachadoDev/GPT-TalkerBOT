defmodule GptTalkerbot.PromptSettings.GroupContextExtractor do
  require Logger

  alias GptTalkerbot.PromptSettings.GroupContext
  alias GptTalkerbot.RuntimeEnvs.GenServer, as: RuntimeEnvs
  alias GptTalkerbotWeb.Services.{OpenAI, Grok}

  @system_prompt """
  Você é um assistente que mantém um resumo de contexto de conversas de grupo.
  Dado o contexto atual (pode estar vazio) e um lote de novas mensagens, atualize o contexto
  para capturar: tópicos discutidos, decisões tomadas, referências importantes e humor geral do grupo.
  Seja conciso — máximo 300 palavras. Responda APENAS com o contexto atualizado, sem explicações.
  """

  @settings %{
    prompt: nil,
    temperature: 0.3,
    frequency_penalty: 0.0,
    presence_penalty: 0.0,
    max_completion_tokens: 400
  }

  @grok_settings %{
    prompt: nil,
    temperature: 0.3,
    reasoning_effort: "none",
    max_completion_tokens: 400
  }

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

    case call_ai(ai_messages) do
      {:ok, body} ->
        case get_in(body, ["choices", Access.at(0), "message", "content"]) do
          nil ->
            Logger.warning("GroupContextExtractor: empty response from AI")

          new_context ->
            GroupContext.update_context(chat_id, String.trim(new_context))
            Logger.info("GroupContextExtractor: updated context for chat #{chat_id}")
        end

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

  defp call_ai(messages) do
    case RuntimeEnvs.get_current_service() do
      :openai ->
        RuntimeEnvs.get_openai_api_key()
        |> OpenAI.new()
        |> OpenAI.gpt_completion(nil, messages, @settings)

      :grok ->
        RuntimeEnvs.get_grok_api_key()
        |> Grok.new()
        |> Grok.grok_completion(nil, messages, @grok_settings)
    end
  end
end
