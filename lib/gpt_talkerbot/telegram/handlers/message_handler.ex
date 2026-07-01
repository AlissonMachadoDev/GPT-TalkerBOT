defmodule GptTalkerbot.Telegram.Handlers.MessageHandler do
  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.{Telegram, SpiceChecker}
  alias GptTalkerbot.{LLM, Memory, MoodTracker, RuntimeEnvs}
  alias GptTalkerbot.Memory.FactExtractor
  alias GptTalkerbot.PromptSettings.{Personality, BotDefinitions, GroupContext}
  alias GptTalkerbot.GroupMessageCache
  alias GptTalkerbot.Telegram.HtmlSanitizer

  @behaviour GptTalkerbot.Telegram.Handlers

  # Um rato robótico não falha com stack trace, falha com estilo
  @error_replies [
    "<i>*fusível de queijo queimado*</i> tenta de novo daqui a pouco 🐀",
    "<i>*ranger de engrenagens*</i> meu cérebro de rato travou. De novo.",
    "Deu ruim aqui no porão dos servidores. Culpa do gato, com certeza.",
    "Erro 404: queijo não encontrado. Tenta de novo."
  ]

  @impl true
  def handle(
        %Message{
          text: text,
          chat_id: chat_id,
          from: %{telegram_id: user_id}
        } = message
      ) do
    MoodTracker.react_to_text(chat_id, text)
    Telegram.send_typing(chat_id)

    current_msg = build_current_message(message)
    history = Memory.get_context(chat_id, user_id, text)
    ai_messages = history ++ [BotDefinitions.current_message_marker(), current_msg]

    system_prompt =
      Personality.build_system_prompt(user_id, chat_id)
      |> append_group_context(chat_id)
      |> append_members(chat_id)
      |> Kernel.<>(BotDefinitions.format_instruction())

    with {:ok, response} <- process_ai_message(user_id, ai_messages, system_prompt) do
      reply = extract_content(response)
      Memory.save_exchange(chat_id, user_id, current_msg.content, reply)
      GroupMessageCache.add_bot_message(chat_id, reply)
      FactExtractor.extract_and_save(user_id, text)
      MoodTracker.bump(chat_id)
      send_message(reply, message)
    else
      {:error, _} -> send_message(Enum.random(@error_replies), message)
    end
  end

  def process_ai_message(user_id, messages, system_prompt) do
    text = messages |> Enum.map_join(" ", & &1.content)
    provider = SpiceChecker.route(text)

    LLM.complete(messages,
      provider: provider,
      user: user_id,
      prompt: system_prompt,
      frequency_penalty: 0.5,
      presence_penalty: 0.6,
      max_tokens: if(provider == :grok, do: 2000, else: 1000)
    )
  end

  # Citação longa no meio da mensagem só dilui o que importa
  @max_quote_length 200

  # A mensagem citada entra embutida na fala atual em vez de virar uma
  # mensagem avulsa no histórico — avulsa ela duplica falas que já estão
  # lá e o modelo lê como se a pessoa tivesse insistido no assunto
  defp build_current_message(%Message{
         text: text,
         from: %{telegram_id: user_id, first_name: name},
         reply_to_message: %{from: %{telegram_id: reply_user_id, first_name: reply_name}} = reply
       }) do
    quoted =
      (reply.caption || reply.text || "")
      |> String.slice(0, @max_quote_length)

    content =
      "#{user_label(name, user_id)} (respondendo a #{user_label(reply_name, reply_user_id)}: \"#{quoted}\"): #{text}"

    %{role: "user", content: content}
  end

  defp build_current_message(%Message{
         text: text,
         from: %{telegram_id: user_id, first_name: name}
       }) do
    %{role: "user", content: "#{user_label(name, user_id)}: #{text}"}
  end

  defp user_label(name, user_id) do
    case Map.get(RuntimeEnvs.get_user_labels(), to_string(user_id)) do
      nil -> name
      label -> "#{name} (#{label})"
    end
  end

  defp extract_content(response) do
    response
    |> get_in(["choices", Access.at(0), "message", "content"])
    |> HtmlSanitizer.truncate()
  end

  defp append_members(prompt, chat_id) do
    prompt <> GptTalkerbot.ChatMembers.prompt_section(chat_id)
  end

  defp append_group_context(prompt, chat_id) do
    case GroupContext.get_context(chat_id) do
      "" ->
        prompt

      context ->
        prompt <>
          "\n\nPano de fundo do grupo — serve só para você entender referências; não traga esses assuntos de volta por conta própria:\n" <>
          context
    end
  end

  defp send_message(text, %{chat_id: chat_id, message_id: message_id}) do
    Telegram.send_message(%{chat_id: chat_id, text: text, reply_to_message_id: message_id, parse_mode: "HTML"})
  end
end
