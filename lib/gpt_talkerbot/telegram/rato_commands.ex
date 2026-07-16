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
    /esquecemsg - apaga a mensagem respondida do contexto/histórico (só admin)
    /faxina   - IA revisa o contexto e remove mensagens degeneradas (só admin)
    /amnesia  - apaga todo o contexto de conversa do chat, preservando fatos/warns/GIFs (só admin)
    /ignore_messages <texto> - mensagens contendo o texto ficam fora do histórico (só admin)
  """

  require Logger

  alias GptTalkerbot.{
    ChatMembers,
    GifMemory,
    GroupMessageCache,
    IgnoredPatterns,
    LLM,
    Memory,
    MoodTracker,
    RuntimeEnvs,
    Warns
  }

  alias GptTalkerbot.Memory.ContextJanitor
  alias GptTalkerbot.PromptSettings.{BotDefinitions, GroupContext}
  alias GptTalkerbot.Telegram.{HtmlSanitizer, RichMessages}
  alias GptTalkerbotWeb.Services.Telegram

  @commands ~w(humor fatos esquece resumo enquete enquete_random sorte ratowarn bangif esquecemsg faxina amnesia ignore_messages)

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
    flertando: "Hoje tô no modo caça-marido. Chega mais que o porão tá quentinho. 😏",
    nostalgico: "Ai, no meu tempo de esgoto o queijo era queijo... saudade viu. 🧀",
    fofoqueiro: "Senta que lá vem história. Tenho cada babado guardado nesses fios... 👀",
    dramatico: "AH, a vida de um rato de metal é uma NOVELA. Uma tragédia em cada válvula. 🎭"
  }

  @resumo_instruction """

  Abaixo está o resumo neutro do que rolou no grupo recentemente. Reescreva como \
  o "resumo do dia" do Ratobô: debochado, curto, tirando sarro dos assuntos e de \
  quem participou, sem inventar fatos que não estejam no resumo.
  """

  def commands, do: @commands

  defp owner_id, do: RuntimeEnvs.get_owner_id()

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
        recap = roast_recap(context)

        case Telegram.send_rich_message(%{
               chat_id: chat_id,
               rich_message: RichMessages.resumo(recap)
             }) do
          {:ok, %{status: 200}} ->
            :ok

          # Rich message recusada não pode calar o /resumo. O recap agora é
          # Markdown, então o fallback vai sem parse_mode — sai com os
          # símbolos crus, mas sai
          _ ->
            reply_plain(message, recap)
        end
    end
  end

  def handle("enquete_random", %{"chat" => %{"id" => chat_id}} = message) do
    members = poll_members(chat_id) |> Enum.shuffle() |> Enum.take(8)

    if length(members) < 2 do
      reply(
        message,
        "Enquete com esse deserto? Preciso conhecer pelo menos 2 pessoas daqui. Falem mais. 🐀"
      )
    else
      Telegram.send_typing(to_string(chat_id))

      question =
        case LLM.complete_text(
               [%{role: "user", content: "Gere a pergunta da enquete."}],
               prompt: RuntimeEnvs.get_default_prompt() <> @enquete_instruction,
               max_tokens: 150
             ) do
          {:ok, q} ->
            q |> String.trim() |> String.trim("\"") |> String.slice(0, 250)

          {:error, _} ->
            "Quem do grupo é mais provável de ser substituído por um rato robótico sem ninguém notar?"
        end

      send_and_remember_poll(chat_id, question, Enum.map(members, &poll_option_with_photo/1))
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
            send_and_remember_poll(chat_id, question, illustrate_member_options(options, chat_id))

          :error ->
            reply(
              message,
              "Minha máquina de enquetes engasgou com essa instrução. Reformula aí. 🐀"
            )
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
        %{
          "chat" => %{"id" => chat_id},
          "from" => %{"id" => issuer_id},
          "reply_to_message" => %{"from" => target} = replied
        } =
          message
      ) do
    if is_admin?(issuer_id) do
      if target["is_bot"] do
        reply(message, "Warn em mim? Eu SOU o regulamento. Petição negada. 🐀")
      else
        count = Warns.increment(chat_id, target["id"], target["first_name"])
        mention = mention(target)
        offending = replied["text"] || replied["caption"] || "(mensagem sem texto)"

        response =
          if count >= Warns.limit() do
            "⚖️ #{mention} atingiu <b>#{Warns.limit()} warns</b>.\n\nMas o Ratobô é misericordioso: ficha limpa, contador zerado, mais uma chance. Não me faça me arrepender. 🐀"
          else
            Telegram.send_typing(to_string(chat_id))
            warn_text = generate_warn(target["first_name"], offending)
            "⚠️ <b>Warn #{count}/#{Warns.limit()}</b> para #{mention}\n\n#{warn_text}"
          end

        Warns.record_entry(%{
          chat_id: to_string(chat_id),
          user_id: to_string(target["id"]),
          first_name: target["first_name"],
          issuer_name: get_in(message, ["from", "first_name"]),
          offending_message: offending,
          request_message: message["text"],
          bot_response: response
        })

        # O perdão vem depois do registro: o 6º warn também entra na ficha,
        # já marcado como perdoado junto com os anteriores
        if count >= Warns.limit(), do: Warns.reset(chat_id, target["id"])

        reply(message, response)
      end
    else
      reply(message, ratowarn_admin_only_message())
    end
  end

  def handle("ratowarn", %{"from" => %{"id" => issuer_id}} = message) do
    if is_admin?(issuer_id) do
      reply(message, "Warn em quem? Responda à mensagem do infrator, não sou vidente. 🐀")
    else
      reply(message, ratowarn_admin_only_message())
    end
  end

  def handle(
        "ignore_messages",
        %{"chat" => %{"id" => chat_id}, "from" => %{"id" => issuer_id}, "text" => text} = message
      ) do
    pattern = command_args(text)

    cond do
      not is_admin?(issuer_id) ->
        reply(message, "Só o admin escolhe o que eu finjo não ver. 🐀")

      pattern == "" ->
        case IgnoredPatterns.list(chat_id) do
          [] ->
            reply(
              message,
              "Uso: /ignore_messages <texto>. Mensagens contendo o texto ficam fora do meu histórico. A lista está vazia."
            )

          patterns ->
            reply(
              message,
              "Finjo não ver mensagens contendo:\n" <>
                Enum.map_join(patterns, "\n", &("• " <> escape_html(&1)))
            )
        end

      true ->
        case IgnoredPatterns.add(chat_id, pattern) do
          :ok ->
            reply(
              message,
              ~s(Anotado. Mensagens com "#{escape_html(pattern)}" não existem pra mim. 🐀)
            )

          :already_exists ->
            reply(message, "Isso eu já finjo não ver.")

          {:error, _} ->
            reply(message, "Minha caneta de censura falhou. Tenta de novo.")
        end
    end
  end

  def handle(
        "esquecemsg",
        %{
          "chat" => %{"id" => chat_id},
          "from" => %{"id" => issuer_id},
          "reply_to_message" => replied
        } = message
      ) do
    text = replied["text"] || replied["caption"] || ""

    cond do
      not is_admin?(issuer_id) ->
        reply(message, "Só o admin edita minha memória na marra. 🐀")

      text == "" ->
        reply(message, "Essa mensagem não tem texto — não tem o que esquecer.")

      true ->
        removed = Memory.forget_by_content(to_string(chat_id), text)
        GroupMessageCache.forget(chat_id, text)

        if removed > 0 do
          reply(
            message,
            "Feito. #{removed} registro(s) incinerados do histórico. Isso nunca aconteceu, e quem imprimiu não fui eu. 🐀🔥"
          )
        else
          reply(message, "Não achei isso no meu histórico — ou já tinha esquecido sozinho.")
        end
    end
  end

  def handle("esquecemsg", %{"from" => %{"id" => issuer_id}} = message) do
    if is_admin?(issuer_id) do
      reply(message, "Esquecer o quê? Responda à mensagem podre que eu queimo o registro.")
    else
      reply(message, "Só o admin edita minha memória na marra. 🐀")
    end
  end

  # Último recurso proporcional: só a memória de conversa do chat evapora.
  # Fatos, warns, GIFs e o resumo extraído ficam — pra isso existe o
  # /cleardatabase, que é a bomba atômica.
  def handle("amnesia", %{"chat" => %{"id" => chat_id}, "from" => %{"id" => issuer_id}} = message) do
    if is_admin?(issuer_id) do
      {removed, _} = Memory.clear_context(to_string(chat_id))
      GroupMessageCache.clear(chat_id)

      reply(
        message,
        "🧠💨 Amnésia seletiva aplicada: #{removed} mensagens de conversa esquecidas. " <>
          "Fatos, warns e GIFs continuam no arquivo — só a fofoca recente evaporou. Quem sou eu mesmo?"
      )
    else
      reply(message, "Amnésia só quando o admin manda. Minha memória não é playground. 🐀")
    end
  end

  def handle("faxina", %{"chat" => %{"id" => chat_id}, "from" => %{"id" => issuer_id}} = message) do
    if is_admin?(issuer_id) do
      Telegram.send_typing(to_string(chat_id))

      case ContextJanitor.sweep(to_string(chat_id)) do
        {:ok, 0, _removed} ->
          reply(message, "Histórico vazio, nada pra revisar. Poeira zero no porão. 🐀")

        {:ok, reviewed, 0} ->
          reply(
            message,
            "Inspeção completa: #{reviewed} mensagens revisadas, nenhuma podre. Meu histórico tá mais limpo que a sua ficha. 🐀"
          )

        {:ok, reviewed, removed} ->
          reply(
            message,
            "🧹 Faxina feita: #{reviewed} mensagens revisadas, <b>#{removed} incineradas</b> por degeneração. O porão agradece."
          )

        {:error, reason} ->
          Logger.warning("RatoCommands: faxina failed: #{inspect(reason)}")

          reply(
            message,
            "Meu inspetor de qualidade travou no meio da vistoria. Tenta de novo daqui a pouco."
          )
      end
    else
      reply(message, "Faxina na minha memória só quem paga meu queijo: o admin. 🐀")
    end
  end

  def handle(
        "bangif",
        %{"chat" => %{"id" => chat_id}, "reply_to_message" => %{"animation" => anim}} = message
      ) do
    case GifMemory.ban(chat_id, anim["file_unique_id"]) do
      :ok ->
        reply(message, "GIF banido da minha memória. Nunca vi, não conheço, não mando mais. 🐀")

      :not_found ->
        reply(message, "Esse GIF nem estava na minha coleção, mas tá anotado o recado.")
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

    texts =
      Enum.map(options, fn
        %{text: text} -> text
        text -> text
      end)

    GroupMessageCache.add_bot_message(
      chat_id,
      ~s([enquete: "#{question}" — opções: #{Enum.join(texts, ", ")}])
    )
  end

  # Foto de perfil na opção deixa a enquete com cara de line-up de suspeitos
  # (Bot API 10.0). Sem foto — privacidade, conta sem foto — sai só o nome.
  defp poll_option_with_photo(%{user_id: user_id, first_name: name}) do
    with {id, ""} <- Integer.parse(user_id),
         {:ok, file_id} <- Telegram.get_user_profile_photo(id) do
      %{text: name, media: %{type: "photo", media: file_id}}
    else
      _ -> %{text: name}
    end
  end

  # Enquete só com quem participa de verdade — todos com o mesmo peso no
  # sorteio. Enquanto o contador não conhece gente o suficiente (grupo
  # recém-migrado), vale a lista completa, como antes.
  defp poll_members(chat_id) do
    members =
      case ChatMembers.list_frequent_members(chat_id) do
        frequent when length(frequent) >= 2 -> frequent
        _ -> ChatMembers.list_members(chat_id)
      end

    Enum.reject(members, &is_nil(&1.first_name))
  end

  # Na /enquete custom o LLM devolve opções em texto; quando uma opção é o
  # nome de alguém da listagem de membros, a foto entra junto
  defp illustrate_member_options(options, chat_id) do
    options
    |> match_member_options(ChatMembers.list_members(chat_id))
    |> Enum.map(fn
      {text, nil} -> text
      {text, member} -> poll_option_with_photo(%{user_id: member.user_id, first_name: text})
    end)
  end

  @doc false
  # Pareia cada opção com um membro pelo nome (sem case/espaços). Nome
  # repetido no grupo não pareia ninguém — melhor sem foto do que com a
  # foto do xará errado.
  def match_member_options(options, members) do
    by_name =
      members
      |> Enum.reject(&is_nil(&1.first_name))
      |> Enum.group_by(&normalize_name(&1.first_name))

    Enum.map(options, fn text ->
      case by_name[normalize_name(text)] do
        [member] -> {text, member}
        _ -> {text, nil}
      end
    end)
  end

  defp normalize_name(name), do: name |> String.trim() |> String.downcase()

  # Texto após o comando: "/enquete melhor pizza" -> "melhor pizza"
  defp command_args(text) do
    case String.split(text, " ", parts: 2) do
      [_command, args] -> String.trim(args)
      _ -> ""
    end
  end

  defp generate_custom_poll(chat_id, instruction) do
    members =
      case poll_members(chat_id) do
        [] -> "(nenhuma pessoa conhecida ainda)"
        active -> Enum.map_join(active, ", ", & &1.first_name)
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

  defp generate_warn(name, offending) do
    user_content = "Infrator: #{name}\nMensagem citada: #{offending}"

    case LLM.complete_text(
           [%{role: "user", content: user_content}],
           prompt: RuntimeEnvs.get_default_prompt() <> @warn_instruction,
           max_tokens: 200
         ) do
      {:ok, text} ->
        text |> String.trim() |> HtmlSanitizer.truncate()

      {:error, _} ->
        "Violação do artigo 7, parágrafo queijo, do Regulamento do Esgoto. Sem recurso."
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

  # O recap sai em Markdown porque vira rich message — tabelas, listas e
  # spoilers entram no repertório do deboche. O HtmlSanitizer não se aplica:
  # ele conserta tags HTML, e aqui não pode haver nenhuma.
  defp roast_recap(context) do
    system_prompt =
      RuntimeEnvs.get_default_prompt() <>
        @resumo_instruction <> BotDefinitions.rich_format_instruction()

    messages = [%{role: "user", content: "Resumo neutro:\n" <> context}]

    case LLM.complete_text(messages, prompt: system_prompt, max_tokens: 500) do
      {:ok, recap} ->
        String.trim(recap)

      {:error, reason} ->
        Logger.warning("RatoCommands: recap AI call failed: #{inspect(reason)}")
        "Meu redator interno travou, vai o rascunho cru mesmo:\n\n" <> context
    end
  end

  defp ratowarn_admin_only_message,
    do: "Somente o admin pode aplicar /ratowarn. Segura o martelo aí. 🐀"

  defp is_admin?(owner_id) when is_integer(owner_id),
    do: is_admin?(Integer.to_string(owner_id))

  defp is_admin?(user_id), do: user_id == owner_id()

  # ClientInputs.SendMessage espera chat_id/message_id como string
  defp reply(%{"chat" => %{"id" => chat_id}, "message_id" => message_id}, text) do
    Telegram.send_message(%{
      chat_id: to_string(chat_id),
      text: text,
      reply_to_message_id: to_string(message_id),
      parse_mode: "HTML"
    })
  end

  # Sem parse_mode: para texto Markdown, que o parse_mode HTML corromperia
  defp reply_plain(%{"chat" => %{"id" => chat_id}, "message_id" => message_id}, text) do
    Telegram.send_message(%{
      chat_id: to_string(chat_id),
      text: text,
      reply_to_message_id: to_string(message_id)
    })
  end
end
