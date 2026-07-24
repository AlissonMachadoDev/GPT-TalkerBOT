defmodule GptTalkerbot.Telegram.Handlers.MessageHandler do
  require Logger

  alias GptTalkerbot.Telegram.Message
  # SpiceChecker desativado no fluxo de chat (ver process_ai_message)
  alias GptTalkerbotWeb.Services.{Telegram, TTS}
  alias GptTalkerbot.{GifMemory, LLM, Memory, PostActions, RuntimeEnvs}
  alias GptTalkerbot.Memory.FactExtractor
  alias GptTalkerbot.PromptSettings.{Personality, BotDefinitions, ContextTools}
  alias GptTalkerbot.GroupMessageCache
  alias GptTalkerbot.Telegram.{HtmlSanitizer, RichMessages}

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
    maybe_send_thinking_draft(message)

    current_msg = build_current_message(message)
    history = Memory.get_context(chat_id, user_id, text)
    ai_messages = history ++ [BotDefinitions.current_message_marker(), current_msg]

    system_prompt =
      Personality.build_system_prompt(user_id, chat_id)
      |> Kernel.<>(ContextTools.prompt_hint())
      |> Kernel.<>(PostActions.instruction())
      |> Kernel.<>(format_instruction_for(message))

    with {:ok, response} <- process_ai_message(user_id, chat_id, ai_messages, system_prompt) do
      {reply, actions} = extract_content(response)
      reply = ensure_text(reply, actions, ai_messages, user_id, chat_id)

      case send_reply(reply, actions, message) do
        :ok ->
          Memory.save_exchange(chat_id, user_id, current_msg.content, reply)
          GroupMessageCache.add_bot_message(chat_id, reply)

        {:error, reason} ->
          # Resposta que o Telegram recusou nunca chegou ao chat: gravar no
          # histórico faria o modelo acreditar num diálogo que não houve — e
          # era assim que respostas envenenadas se reinfiltravam no contexto
          Logger.warning(
            "MessageHandler: reply not delivered, not saved to context: #{inspect(reason)}"
          )
      end

      FactExtractor.extract_and_save(user_id, text)
    else
      {:error, _} -> send_message(Enum.random(@error_replies), message)
    end
  end

  def process_ai_message(user_id, chat_id, messages, system_prompt) do
    # SpiceChecker desativado: o chat responde sempre pelo Grok. O OpenAI ficou
    # só para a extração de fatos (ver FactExtractor). Para reativar o
    # roteamento por moderação, descomente as duas linhas abaixo e troque
    # `provider = :grok` por `provider = SpiceChecker.route(text)`.
    # text = messages |> Enum.map_join(" ", & &1.content)
    # provider = SpiceChecker.route(text)
    provider = :grok

    LLM.complete_with_tools(messages,
      provider: provider,
      user: user_id,
      prompt: system_prompt,
      tools: ContextTools.specs(),
      tool_executor: fn name, args -> ContextTools.execute(name, args, chat_id) end,
      # Só chegam ao OpenAI (o LLM ignora penalties no branch do Grok).
      # Valores altos acumulam ao longo da geração e degeneram texto longo
      # e repetitivo (tabelas) — 0.2 segura repetição sem esse risco
      frequency_penalty: 0.2,
      presence_penalty: 0.2,
      max_tokens: 2000
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

  # No privado a resposta vira rich message em Markdown (tabelas, títulos,
  # listas); no grupo continua parse_mode HTML, que não aceita nada disso
  defp format_instruction_for(%Message{chat_type: "private"}),
    do: BotDefinitions.rich_format_instruction()

  defp format_instruction_for(_message), do: BotDefinitions.format_instruction()

  # Draft com o bloco "thinking" nativo (Bot API 10.1) — a API só aceita em
  # chat privado; no grupo fica o "digitando..." de sempre. Fire-and-forget:
  # se a chamada falhar, o typing já cobre o feedback.
  defp maybe_send_thinking_draft(%Message{
         chat_type: "private",
         chat_id: chat_id,
         message_id: message_id
       }) do
    with {chat, ""} <- Integer.parse(chat_id),
         {draft, ""} <- Integer.parse(message_id) do
      Telegram.send_rich_message_draft(%{
        chat_id: chat,
        draft_id: draft,
        rich_message: RichMessages.thinking_draft("Farejando uma resposta... 🐀")
      })
    end
  end

  defp maybe_send_thinking_draft(_message), do: :ok

  defp send_reply(reply, actions, message) do
    result =
      cond do
        :audio in actions -> send_with_audio(reply, message)
        :gif in actions -> send_with_gif(reply, message)
        message.chat_type == "private" -> send_rich_reply(reply, message)
        true -> send_message(reply, message)
      end

    delivered(result)
  end

  # Normaliza o resultado do envio: só conta como entregue o que o
  # Telegram aceitou — é o que decide se a resposta entra no histórico
  defp delivered(:ok), do: :ok
  defp delivered({:ok, %{status: 200}}), do: :ok
  defp delivered({:ok, %{status: status, body: body}}), do: {:error, {status, body}}
  defp delivered(other), do: {:error, other}

  # No privado o draft "thinking" precisa ser finalizado com sendRichMessage —
  # uma mensagem comum deixaria o rascunho evaporar sem virar resposta.
  # Rich recusada não pode calar o rato: a resposta é Markdown, então o
  # fallback vai sem parse_mode (símbolos crus, mas nunca silêncio).
  defp send_rich_reply(reply, %{chat_id: chat_id, message_id: message_id} = message) do
    payload =
      %{chat_id: chat_id, rich_message: RichMessages.markdown(reply)}
      |> put_reply_parameters(message_id)

    case Telegram.send_rich_message(payload) do
      {:ok, %{status: 200}} -> :ok
      _ -> send_plain_message(reply, message)
    end
  end

  defp send_plain_message(text, %{chat_id: chat_id, message_id: message_id}) do
    Telegram.send_message(%{chat_id: chat_id, text: text, reply_to_message_id: message_id})
  end

  defp put_reply_parameters(payload, message_id) do
    case Integer.parse(message_id) do
      {id, ""} -> Map.put(payload, :reply_parameters, %{message_id: id})
      _ -> payload
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
        # O que decide a entrega é o texto; o GIF avulso é bônus
        result = send_message(reply, message)
        Telegram.send_animation(%{chat_id: to_string(chat_id), animation: gif.file_id})
        result
    end
  end

  # O modelo sinalizou [[ratobo:audio]]: a resposta vira nota de voz. O texto é
  # a fala (limpo de HTML pro TTS) e vai junto como legenda. Qualquer falha
  # (TTS fora, voz recusada) cai pro texto normal — o rato nunca fica mudo.
  defp send_with_audio(reply, %{chat_id: chat_id, message_id: message_id} = message) do
    # O texto vai com as audio tags do v3 pro sintetizador; a legenda e o
    # fallback de texto saem sem elas, pra ninguém ler "[sarcastic]" escrito.
    with spoken when spoken != "" <- plain_text(reply),
         {:ok, audio} <- TTS.synthesize(spoken) do
      caption = spoken |> PostActions.strip_audio_tags() |> String.slice(0, @caption_max)

      %{
        chat_id: to_string(chat_id),
        voice: audio,
        caption: caption,
        reply_to_message_id: message_id
      }
      |> Telegram.send_voice()
      |> case do
        {:ok, %{status: 200}} -> :ok
        _ -> send_message(PostActions.strip_audio_tags(reply), message)
      end
    else
      _ -> send_message(PostActions.strip_audio_tags(reply), message)
    end
  end

  defp plain_text(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end

  defp send_message(text, %{chat_id: chat_id, message_id: message_id} = message) do
    if RichMessages.needs_rich_html?(text) do
      send_rich_html(text, message)
    else
      Telegram.send_message(%{
        chat_id: chat_id,
        text: text,
        reply_to_message_id: message_id,
        parse_mode: "HTML"
      })
    end
  end

  # HTML com bloco que o parse_mode não reconhece (tabela, lista, título)
  # vai como rich message, que reconhece. Se ela for recusada, os blocos
  # são achatados pra texto e a resposta sai assim mesmo: nunca silêncio.
  defp send_rich_html(text, %{chat_id: chat_id, message_id: message_id}) do
    payload =
      %{chat_id: chat_id, rich_message: RichMessages.from_html(text)}
      |> put_reply_parameters(message_id)

    case Telegram.send_rich_message(payload) do
      {:ok, %{status: 200}} ->
        :ok

      _ ->
        Telegram.send_message(%{
          chat_id: chat_id,
          text: RichMessages.flatten_html(text),
          reply_to_message_id: message_id,
          parse_mode: "HTML"
        })
    end
  end
end
