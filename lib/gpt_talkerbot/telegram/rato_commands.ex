defmodule GptTalkerbot.Telegram.RatoCommands do
  @moduledoc """
  Comandos públicos in-character do Ratobô.

    /humor    - mostra o mood atual do chat
    /fatos    - lista o que o bot sabe sobre o usuário
    /esquece  - apaga os fatos guardados sobre o usuário
    /resumo   - recap debochado do contexto recente do grupo
    /enquete_random - enquete maliciosa com os membros do grupo como opções
    /enquete <instrução> - enquete gerada a partir da instrução dada
    /sorte    - animação nativa de dado/dardo/caça-níquel
    /ratowarn - warn debochado para a mensagem respondida (perdão aos 6)
    /bangif   - bane da memória o GIF respondido (controle de conteúdo)
  """

  require Logger

  alias GptTalkerbot.{ChatMembers, GifMemory, GroupMessageCache, LLM, Memory, MoodTracker, RuntimeEnvs, Warns}
  alias GptTalkerbot.PromptSettings.{BotDefinitions, GroupContext}
  alias GptTalkerbot.Telegram.HtmlSanitizer
  alias GptTalkerbotWeb.Services.Telegram

  @commands ~w(humor fatos esquece resumo enquete enquete_random sorte ratowarn bangif)

  @dice_emojis ["🎲", "🎯", "🏀", "⚽", "🎳", "🎰"]

  @enquete_instruction """

  Crie UMA pergunta de enquete maliciosa e debochada sobre o grupo, do tipo \
  "Quem é mais provável de...?" ou "Quem do grupo...?", com duplo sentido. \
  Máximo 250 caracteres, texto puro sem HTML nem aspas. Responda APENAS com a pergunta.
  """

  @enquete_custom_instruction """

  Crie uma enquete de grupo baseada na instrução do usuário, mantendo seu tom \
  debochado. Se a instrução pedir pessoas do grupo, use os nomes da lista fornecida.
  Responda APENAS com JSON no formato: {"question": "...", "options": ["...", "..."]}
  question: máximo 250 caracteres. options: de 2 a 8 itens, máximo 90 caracteres \
  cada, texto puro sem HTML. Não inclua nada além do JSON.
  """

  @warn_instruction """

  Você vai emitir um AVISO OFICIAL (warn) debochado para uma pessoa do grupo, \
  por causa da mensagem dela citada abaixo. Tom de burocracia de esgoto: cite o \
  "regulamento" inventado que ela violou. Curto, no máximo 3 frases, texto puro sem HTML.
  """

  @mood_lines %{
    normal: "Tudo nos conformes no porão. Humor estável, estoque de queijo em dia. 🧀",
    grumpy: "Péssimo. Não me testa hoje. 🐀",
    excited: "HOJE TÁ BOM DEMAIS! Pergunta qualquer coisa, EU RESPONDO TUDO! ⚡",
    sarcastic: "Ah, meu humor? Impecável. Como sempre. Nota-se, né? 🙄",
    sleepy: "zzz... hã? tô acordado, tô acordado... o que você queria mesmo? 😴"
  }

  @resumo_instruction """

  Abaixo está o resumo neutro do que rolou no grupo recentemente. Reescreva como \
  o "resumo do dia" do Ratobô: debochado, curto, tirando sarro dos assuntos e de \
  quem participou, sem inventar fatos que não estejam no resumo.
  """

  def commands, do: @commands

  def handle("humor", %{"chat" => %{"id" => chat_id}} = message) do
    mood = MoodTracker.get_mood(chat_id)
    reply(message, Map.get(@mood_lines, mood, @mood_lines.normal))
  end

  def handle("fatos", %{"from" => %{"id" => user_id}} = message) do
    case Memory.get_user_facts(to_string(user_id)) do
      [] ->
        reply(message, "Meus sensores ainda não captaram nada sobre você. Suspeito. 🐀")

      facts ->
        facts_text = Enum.map_join(facts, "\n", fn f -> "• <b>#{f.key}</b>: #{f.value}" end)

        reply(
          message,
          "O que meus sensores captaram sobre você:\n\n#{facts_text}\n\n<i>/esquece se quiser que eu formate essa memória.</i>"
        )
    end
  end

  def handle("esquece", %{"from" => %{"id" => user_id}} = message) do
    Memory.clear_user_facts(to_string(user_id))
    reply(message, "Feito. Memória formatada, disco limpo. Você é um estranho pra mim agora. 🐀")
  end

  def handle("resumo", %{"chat" => %{"id" => chat_id}} = message) do
    case GroupContext.get_context(chat_id) do
      "" ->
        reply(message, "Resumo do dia: nada. Absolutamente nada digno de nota aconteceu aqui. 🧀")

      context ->
        Telegram.send_typing(to_string(chat_id))
        reply(message, roast_recap(context))
    end
  end

  def handle("enquete_random", %{"chat" => %{"id" => chat_id}} = message) do
    names = ChatMembers.list_names(chat_id, 10) |> Enum.shuffle() |> Enum.take(8)

    if length(names) < 2 do
      reply(message, "Enquete com esse deserto? Preciso conhecer pelo menos 2 pessoas daqui. Falem mais. 🐀")
    else
      Telegram.send_typing(to_string(chat_id))

      question =
        case LLM.complete_text(
               [%{role: "user", content: "Gere a pergunta da enquete."}],
               prompt: RuntimeEnvs.get_default_prompt() <> @enquete_instruction,
               max_tokens: 150
             ) do
          {:ok, q} -> q |> String.trim() |> String.trim("\"") |> String.slice(0, 250)
          {:error, _} -> "Quem do grupo é mais provável de ser substituído por um rato robótico sem ninguém notar?"
        end

      send_and_remember_poll(chat_id, question, names)
    end
  end

  def handle("enquete", %{"chat" => %{"id" => chat_id}, "text" => text} = message) do
    case command_args(text) do
      "" ->
        reply(
          message,
          "Enquete sobre o quê? Manda /enquete <instrução>. Ou usa /enquete_random que eu invento a maldade sozinho."
        )

      instruction ->
        Telegram.send_typing(to_string(chat_id))

        case generate_custom_poll(chat_id, instruction) do
          {:ok, question, options} ->
            send_and_remember_poll(chat_id, question, options)

          :error ->
            reply(message, "Minha máquina de enquetes engasgou com essa instrução. Reformula aí. 🐀")
        end
    end
  end

  def handle("enquete", message) do
    reply(message, "Enquete sobre o quê? Manda /enquete <instrução>.")
  end

  def handle("sorte", %{"chat" => %{"id" => chat_id}}) do
    Telegram.send_dice(to_string(chat_id), Enum.random(@dice_emojis))
  end

  def handle(
        "ratowarn",
        %{"chat" => %{"id" => chat_id}, "reply_to_message" => %{"from" => target} = replied} =
          message
      ) do
    if target["is_bot"] do
      reply(message, "Warn em mim? Eu SOU o regulamento. Petição negada. 🐀")
    else
      count = Warns.increment(chat_id, target["id"], target["first_name"])
      mention = mention(target)

      if count >= Warns.limit() do
        Warns.reset(chat_id, target["id"])

        reply(
          message,
          "⚖️ #{mention} atingiu <b>#{Warns.limit()} warns</b>.\n\nMas o Ratobô é misericordioso: ficha limpa, contador zerado, mais uma chance. Não me faça me arrepender. 🐀"
        )
      else
        Telegram.send_typing(to_string(chat_id))
        warn_text = generate_warn(target["first_name"], replied)
        reply(message, "⚠️ <b>Warn #{count}/#{Warns.limit()}</b> para #{mention}\n\n#{warn_text}")
      end
    end
  end

  def handle("ratowarn", message) do
    reply(message, "Warn em quem? Responda à mensagem do infrator, não sou vidente. 🐀")
  end

  def handle("bangif", %{"chat" => %{"id" => chat_id}, "reply_to_message" => %{"animation" => anim}} = message) do
    case GifMemory.ban(chat_id, anim["file_unique_id"]) do
      :ok -> reply(message, "GIF banido da minha memória. Nunca vi, não conheço, não mando mais. 🐀")
      :not_found -> reply(message, "Esse GIF nem estava na minha coleção, mas tá anotado o recado.")
    end
  end

  def handle("bangif", message) do
    reply(message, "Banir qual GIF? Responda ao GIF condenado que eu apago da memória.")
  end

  def handle(_command, _message), do: :ok

  # O bot não recebe os próprios updates pelo webhook, então a enquete entra
  # no buffer do grupo aqui — sem isso o /resumo nunca ficaria sabendo dela
  defp send_and_remember_poll(chat_id, question, options) do
    Telegram.send_poll(%{chat_id: to_string(chat_id), question: question, options: options})

    GroupMessageCache.add_bot_message(
      chat_id,
      ~s([enquete: "#{question}" — opções: #{Enum.join(options, ", ")}])
    )
  end

  # Texto após o comando: "/enquete melhor pizza" -> "melhor pizza"
  defp command_args(text) do
    case String.split(text, " ", parts: 2) do
      [_command, args] -> String.trim(args)
      _ -> ""
    end
  end

  defp generate_custom_poll(chat_id, instruction) do
    members =
      case ChatMembers.list_names(chat_id, 10) do
        [] -> "(nenhuma pessoa conhecida ainda)"
        names -> Enum.join(names, ", ")
      end

    user_content = "Pessoas do grupo: #{members}\n\nInstrução da enquete: #{instruction}"

    with {:ok, content} <-
           LLM.complete_text(
             [%{role: "user", content: user_content}],
             prompt: RuntimeEnvs.get_default_prompt() <> @enquete_custom_instruction,
             max_tokens: 400
           ),
         {:ok, %{"question" => question, "options" => options}} <-
           content |> strip_code_fences() |> Jason.decode(),
         true <- is_binary(question),
         options when length(options) >= 2 <-
           options |> Enum.filter(&is_binary/1) |> Enum.take(10) do
      {:ok, String.slice(question, 0, 250), Enum.map(options, &String.slice(&1, 0, 100))}
    else
      _ -> :error
    end
  end

  defp strip_code_fences(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/\s*```\z/, "")
  end

  defp generate_warn(name, replied) do
    offending = replied["text"] || replied["caption"] || "(mensagem sem texto)"

    user_content = "Infrator: #{name}\nMensagem citada: #{offending}"

    case LLM.complete_text(
           [%{role: "user", content: user_content}],
           prompt: RuntimeEnvs.get_default_prompt() <> @warn_instruction,
           max_tokens: 200
         ) do
      {:ok, text} -> text |> String.trim() |> HtmlSanitizer.truncate()
      {:error, _} -> "Violação do artigo 7, parágrafo queijo, do Regulamento do Esgoto. Sem recurso."
    end
  end

  defp mention(%{"id" => id} = user) do
    name = escape_html(user["first_name"] || "alguém")
    ~s(<a href="tg://user?id=#{id}">#{name}</a>)
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp roast_recap(context) do
    system_prompt =
      RuntimeEnvs.get_default_prompt() <>
        @resumo_instruction <> BotDefinitions.format_instruction()

    messages = [%{role: "user", content: "Resumo neutro:\n" <> context}]

    case LLM.complete_text(messages, prompt: system_prompt, max_tokens: 500) do
      {:ok, recap} ->
        HtmlSanitizer.truncate(recap)

      {:error, reason} ->
        Logger.warning("RatoCommands: recap AI call failed: #{inspect(reason)}")
        "Meu redator interno travou, vai o rascunho cru mesmo:\n\n" <> context
    end
  end

  # ClientInputs.SendMessage espera chat_id/message_id como string
  defp reply(%{"chat" => %{"id" => chat_id}, "message_id" => message_id}, text) do
    Telegram.send_message(%{
      chat_id: to_string(chat_id),
      text: text,
      reply_to_message_id: to_string(message_id),
      parse_mode: "HTML"
    })
  end
end
