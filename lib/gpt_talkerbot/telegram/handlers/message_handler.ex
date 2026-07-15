defmodule GptTalkerbot.Telegram.Handlers.MessageHandler do
  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.{Telegram, SpiceChecker}
  alias GptTalkerbot.{GifMemory, LLM, Memory, PostActions, RuntimeEnvs}
  alias GptTalkerbot.Memory.FactExtractor
  alias GptTalkerbot.PromptSettings.{Personality, BotDefinitions, ContextTools}
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
    Telegram.send_typing(chat_id)

    current_msg = build_current_message(message)
    history = Memory.get_context(chat_id, user_id, text)
    ai_messages = history ++ [BotDefinitions.current_message_marker(), current_msg]

    system_prompt =
      Personality.build_system_prompt(user_id, chat_id)
      |> Kernel.<>(ContextTools.prompt_hint())
      |> Kernel.<>(PostActions.instruction())
      |> Kernel.<>(BotDefinitions.format_instruction())

    with {:ok, response} <- process_ai_message(user_id, chat_id, ai_messages, system_prompt) do
      {reply, actions} = extract_content(response)
      reply = ensure_text(reply, actions, ai_messages, user_id, chat_id)
      send_reply(reply, actions, message)
      Memory.save_exchange(chat_id, user_id, current_msg.content, reply)
      GroupMessageCache.add_bot_message(chat_id, reply)
      FactExtractor.extract_and_save(user_id, text)
    else
      {:error, _} -> send_message(Enum.random(@error_replies), message)
    end
  end

  def process_ai_message(user_id, chat_id, messages, system_prompt) do
    text = messages |> Enum.map_join(" ", & &1.content)
    provider = SpiceChecker.route(text)

    LLM.complete_with_tools(messages,
      provider: provider,
      user: user_id,
      prompt: system_prompt,
      tools: ContextTools.specs(),
      tool_executor: fn name, args -> ContextTools.execute(name, args, chat_id) end,
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
         quote_text: quote_text,
         from: %{telegram_id: user_id, first_name: name},
         reply_to_message: %{from: %{telegram_id: reply_user_id, first_name: reply_name}} = reply
       }) do
    # Se a pessoa citou um trecho específico (TextQuote), ele vale mais que
    # a mensagem inteira
    quoted =
      (quote_text || reply.caption || reply.text || "")
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

  # Resposta que é só o marcador de GIF vira string vazia depois do strip —
  # sem isso o GIF sai pro usuário sem legenda nenhuma, e o content vazio
  # também derruba o validate_required do histórico. Vale a pena pagar uma
  # segunda completion aqui (caso raro) pra legenda ainda sair da IA
  @blank_gif_replies [
    "🐀",
    "toma",
    "achei isso pra você",
    "não tinha o que dizer, mas tinha o GIF"
  ]

  defp ensure_text("", actions, ai_messages, user_id, chat_id) do
    if :gif in actions, do: gif_caption(ai_messages, user_id, chat_id), else: "..."
  end

  defp ensure_text(reply, _actions, _ai_messages, _user_id, _chat_id), do: reply

  defp gif_caption(ai_messages, user_id, chat_id) do
    caption_prompt =
      Personality.build_system_prompt(user_id, chat_id) <>
        "\n\nVocê decidiu anexar um GIF a essa resposta mas não escreveu nenhum texto. " <>
        "Escreva agora só a frase curta que serviria de legenda pro GIF, sem mencionar " <>
        "o GIF nem o marcador."

    case LLM.complete_text(ai_messages, prompt: caption_prompt, user: user_id, max_tokens: 60) do
      {:ok, text} when is_binary(text) and text != "" -> HtmlSanitizer.truncate(text)
      _ -> Enum.random(@blank_gif_replies)
    end
  end

  defp extract_content(response) do
    {clean, actions} =
      response
      |> get_in(["choices", Access.at(0), "message", "content"])
      |> PostActions.extract()

    {HtmlSanitizer.truncate(clean), actions}
  end

  defp send_reply(reply, actions, message) do
    if :gif in actions do
      send_with_gif(reply, message)
    else
      send_message(reply, message)
    end
  end

  # Limite de caption do Telegram; acima disso o texto vai como mensagem
  # normal e o GIF sai em seguida, sem legenda
  @caption_max 1024

  defp send_with_gif(reply, %{chat_id: chat_id, message_id: message_id} = message) do
    gif = GifMemory.random_gif(chat_id)

    cond do
      gif == nil ->
        send_message(reply, message)

      String.length(reply) <= @caption_max ->
        %{
          chat_id: to_string(chat_id),
          animation: gif.file_id,
          caption: reply,
          parse_mode: "HTML",
          reply_to_message_id: message_id
        }
        |> Telegram.send_animation()
        |> case do
          {:ok, %{status: 200}} -> :ok
          # GIF recusado (apagado no Telegram, caption inválida...) não pode
          # engolir a resposta: ela sai como mensagem de texto normal
          _ -> send_message(reply, message)
        end

      true ->
        send_message(reply, message)
        Telegram.send_animation(%{chat_id: to_string(chat_id), animation: gif.file_id})
    end
  end

  defp send_message(text, %{chat_id: chat_id, message_id: message_id}) do
    Telegram.send_message(%{chat_id: chat_id, text: text, reply_to_message_id: message_id, parse_mode: "HTML"})
  end
end
