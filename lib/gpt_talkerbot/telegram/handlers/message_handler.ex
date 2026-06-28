defmodule GptTalkerbot.Telegram.Handlers.MessageHandler do
  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.{Grok, OpenAI, Telegram, SpiceChecker}
  alias GptTalkerbot.Memory
  alias GptTalkerbot.Memory.FactExtractor
  alias GptTalkerbot.PromptSettings.{Personality, BotDefinitions}
  alias GptTalkerbot.RuntimeEnvs.GenServer, as: RuntimeEnvs

  @behaviour GptTalkerbot.Telegram.Handlers

  @impl true
  def handle(
        %Message{
          text: text,
          chat_id: chat_id,
          from: %{telegram_id: user_id, first_name: name},
          reply_to_message:
            %{from: %{telegram_id: reply_user_id, first_name: reply_name}} = reply_to_message
        } = message
      ) do
    reply_text = reply_to_message.caption || reply_to_message.text
    history = Memory.get_context(chat_id, user_id)

    replied_msg = build_message(reply_text, reply_name, reply_user_id)
    current_msg = build_message(text, name, user_id)
    system_prompt = Personality.build_system_prompt(user_id) <> BotDefinitions.format_instruction()

    with {:ok, response} <- process_ai_message(user_id, history ++ [replied_msg, current_msg], system_prompt) do
      reply = extract_content(response)
      Memory.save_reply_exchange(chat_id, user_id, replied_msg.content, current_msg.content, reply)
      FactExtractor.extract_and_save(user_id, text)
      RuntimeEnvs.increment_messages()
      send_message(reply, message)
    else
      {:error, _} -> send_message("Erro ao processar mensagem", message)
    end
  end

  def handle(
        %Message{
          text: text,
          chat_id: chat_id,
          from: %{telegram_id: user_id, first_name: name}
        } = message
      ) do
    history = Memory.get_context(chat_id, user_id)
    current = build_message(text, name, user_id)
    system_prompt = Personality.build_system_prompt(user_id) <> BotDefinitions.format_instruction()

    with {:ok, response} <- process_ai_message(user_id, history ++ [current], system_prompt) do
      reply = extract_content(response)
      Memory.save_exchange(chat_id, user_id, current.content, reply)
      FactExtractor.extract_and_save(user_id, text)
      RuntimeEnvs.increment_messages()
      send_message(reply, message)
    else
      {:error, _} -> send_message("Erro ao processar mensagem", message)
    end
  end

  def process_ai_message(user_id, messages, system_prompt) do
    text = messages |> Enum.map_join(" ", & &1.content)

    case SpiceChecker.route(text) do
      :openai ->
        RuntimeEnvs.get_openai_api_key()
        |> OpenAI.new()
        |> OpenAI.gpt_completion(user_id, messages, openai_settings(system_prompt))

      :grok ->
        RuntimeEnvs.get_grok_api_key()
        |> Grok.new()
        |> Grok.grok_completion(user_id, messages, grok_settings(system_prompt))
    end
  end

  defp build_message(text, name, user_id) do
    %{role: "user", content: "#{user_label(name, user_id)}: #{text}"}
  end

  defp user_label(name, user_id) do
    case Map.get(RuntimeEnvs.get_user_labels(), to_string(user_id)) do
      nil -> name
      label -> "#{name} (#{label})"
    end
  end

  defp openai_settings(prompt) do
    %{
      prompt: prompt,
      temperature: RuntimeEnvs.get_temperature(),
      frequency_penalty: 0.5,
      presence_penalty: 0.6,
      max_completion_tokens: 1000
    }
  end

  defp grok_settings(prompt) do
    %{
      prompt: prompt,
      temperature: RuntimeEnvs.get_temperature(),
      reasoning_effort: "none",
      max_completion_tokens: 2000
    }
  end

  defp extract_content(response) do
    response
    |> get_in(["choices", Access.at(0), "message", "content"])
    |> String.split_at(3500)
    |> elem(0)
  end

  defp send_message(text, %{chat_id: chat_id, message_id: message_id}) do
    Telegram.send_message(%{chat_id: chat_id, text: text, reply_to_message_id: message_id, parse_mode: "HTML"})
  end
end
