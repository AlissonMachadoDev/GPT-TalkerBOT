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
    service = RuntimeEnvs.get_current_service()
    Logger.info("GroupContextExtractor: starting extraction chat=#{chat_id} messages=#{length(messages)} service=#{service}")

    current_context = GroupContext.get_context(chat_id)

    if current_context == "" do
      Logger.info("GroupContextExtractor: no existing context chat=#{chat_id} — building from scratch")
    else
      Logger.info("GroupContextExtractor: existing context chat=#{chat_id} length=#{String.length(current_context)}")
    end

    messages_text = format_messages(messages)
    Logger.info("GroupContextExtractor: formatted messages chat=#{chat_id}\n#{messages_text}")

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

    Logger.info("GroupContextExtractor: calling AI chat=#{chat_id} service=#{service}")

    case call_ai(ai_messages, service) do
      {:ok, body} ->
        case get_in(body, ["choices", Access.at(0), "message", "content"]) do
          nil ->
            Logger.warning("GroupContextExtractor: AI returned empty content chat=#{chat_id} body=#{inspect(body)}")

          new_context ->
            trimmed = String.trim(new_context)
            Logger.info("GroupContextExtractor: AI extraction ok chat=#{chat_id} new_length=#{String.length(trimmed)}")
            Logger.info("GroupContextExtractor: new context chat=#{chat_id} content=\"#{String.slice(trimmed, 0, 150)}...\"")
            GroupContext.update_context(chat_id, trimmed)
        end

      {:error, reason} ->
        Logger.error("GroupContextExtractor: AI call failed chat=#{chat_id} reason=#{inspect(reason)}")
    end
  end

  defp format_messages(messages) do
    Enum.map_join(messages, "\n", fn m ->
      ts = NaiveDateTime.to_time(m.inserted_at) |> Time.to_string() |> String.slice(0, 5)
      "[#{ts}] #{m.sender_name}: #{m.content}"
    end)
  end

  defp call_ai(messages, :openai) do
    Logger.info("GroupContextExtractor: using OpenAI")
    RuntimeEnvs.get_openai_api_key()
    |> OpenAI.new()
    |> OpenAI.gpt_completion(nil, messages, @settings)
  end

  defp call_ai(messages, :grok) do
    Logger.info("GroupContextExtractor: using Grok")
    RuntimeEnvs.get_grok_api_key()
    |> Grok.new()
    |> Grok.grok_completion(nil, messages, @grok_settings)
  end
end
