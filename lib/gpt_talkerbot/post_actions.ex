defmodule GptTalkerbot.PostActions do
  @moduledoc """
  Diretivas de pós-ação embutidas na resposta do LLM.

  Ações que não mudam o texto da resposta (anexar um GIF) não justificam
  outra rodada de tool calling — o modelo sinaliza com um marcador no fim
  da resposta e o pipeline executa depois de extraí-lo.

  O marcador é namespaced ([[ratobo:...]]) de propósito: usuário digitando
  o marcador numa mensagem não aciona nada (só a saída do bot é parseada),
  e qualquer variante — inclusive inventada pelo modelo — é removida do
  texto antes do envio, execute ou não.
  """

  alias GptTalkerbot.RuntimeEnvs

  @gif_directive ~r/\[\[\s*ratobo:\s*gif\s*\]\]/iu
  @audio_directive ~r/\[\[\s*ratobo:\s*audio\s*\]\]/iu

  # Busca por nome/personagem: bate contra o título do modelo cadastrado na
  # biblioteca do provedor (Fish `title`, ElevenLabs `search` por nome). Só
  # acha se existir um modelo com esse nome — serve pra pessoa/personagem
  # conhecido, não pra descrição de humor (isso é o próximo marcador).
  @voice_name_directive ~r/\[\[\s*ratobo:\s*voice:\s*nome:\s*([^\]]{1,60}?)\s*\]\]/iu

  # Busca por estilo: vocabulário FIXO (ver @instruction), não texto livre —
  # texto livre não bate com título de modelo nem com tag/label cadastrada.
  # As palavras viram gender/age (ElevenLabs) ou tag (Fish) — ver VoiceSearch.
  @voice_style_directive ~r/\[\[\s*ratobo:\s*voice:\s*estilo:\s*([^\]]{1,60}?)\s*\]\]/iu

  # Mesma sintaxe dos dois de cima, mas capturando o modo (nome|estilo) junto
  # — usado só pra separar falas de diálogo multi-voz (ver voice_turns/1),
  # não pra sinalizar a ação de override de uma fala só (isso já é feito
  # pelos dois directives acima, independentes)
  @voice_turn_directive ~r/\[\[\s*ratobo:\s*voice:\s*(nome|estilo):\s*([^\]]{1,60}?)\s*\]\]/iu

  # Modo bipolar: o elenco da cena declarado UMA vez, e as falas escritas como
  # roteiro ("Fulano: ..."). Evita repetir o marcador de voz em cada fala — o
  # que não é só verbosidade: resolver o elenco de uma vez troca uma busca por
  # fala por uma busca por personagem (ver VoiceSearch, que gasta até duas
  # requisições em cada busca por nome).
  @bipolar_directive ~r/\[\[\s*ratobo:\s*bipolar:\s*([^\]]{1,200}?)\s*\]\]/iu

  # O limite de 200 acompanha o do elenco acima; com {0,60} (que bastava pros
  # marcadores antigos) um [[ratobo:bipolar:...]] de quatro nomes escapava da
  # limpeza e aparecia escrito na resposta.
  @any_directive ~r/\[\[\s*ratobo:[^\]]{0,200}\]\]/iu

  # Linha de roteiro: "Nome: fala". O prefixo é curto de propósito — frase
  # comum terminada em dois-pontos ("Olha só essa cena:") não deve virar fala.
  # Só conta mesmo se o prefixo casar com alguém do elenco (ver script_turns/2).
  @script_line ~r/^\s*([^:\n]{1,40}):\s*(.*)$/u

  # Teto do elenco. A ElevenLabs documenta 10 vozes distintas e a Fish não
  # publica número, mas quatro personagens já é mais gente do que uma nota de
  # voz de piada comporta — e cada um a mais é outra busca de voz.
  @max_cast 4

  # Direção de entrega entre colchetes: tanto as audio tags curtas do eleven_v3
  # ([sarcastic], [laughs harder]) quanto a frase inteira que o drama-3 aceita
  # ([quase rindo, fingindo pena]). Os dois modelos leem isso como instrução de
  # atuação, então fica no texto que vai pro sintetizador — mas some da legenda
  # e do fallback de texto. Começar por letra e não aceitar dígito preserva
  # colchetes de usuário como [2x1] ou [1]; não aceitar ':' preserva a diretiva
  # [[ratobo:...]], que de todo modo já tem colchete duplo.
  @audio_tag ~r/\[\p{L}[\p{L} ,'’-]{1,79}\]/u

  # Tags prosódicas do drama-3, que marcam um trecho da fala em vez de dirigir
  # a frase toda. Vêm entre <> como HTML, mas nenhuma colide com as tags que o
  # Telegram aceita (b, i, u, s, code, pre, a, blockquote, tg-spoiler), então
  # speech_text/1 consegue separar umas das outras.
  @prosody_tag ~r/<\/?(?:whisper|emphasis|soft|fast|slow|stress|forceful)>/i

  # Vocabulário fixo do marcador de estilo — o modelo só pode combinar
  # palavras daqui. Fora dela, VoiceSearch ignora a palavra (não interrompe a
  # busca, mas se nenhuma bater a busca fica vazia e cai na voz default).
  @style_words ~w(feminina masculina jovem adulta idosa grave doce agressiva debochada)

  def style_words, do: @style_words

  @gif_instruction "\n\nPara anexar um GIF aleatório da sua coleção à resposta, termine com o " <>
                     "marcador [[ratobo:gif]] em uma linha própria. Use raramente, só quando um " <>
                     "GIF somar à piada. O marcador nunca pode ser a resposta inteira: escreva " <>
                     "sempre uma frase de verdade antes dele, que sirva de legenda pro GIF. " <>
                     "Nunca mencione o marcador no texto nem o use em enquetes."

  @audio_instruction "\n\nQuando pedirem um áudio, nota de voz ou pra você 'falar' algo, termine " <>
                       "a resposta com o marcador [[ratobo:audio]] em uma linha própria — ela " <>
                       "vira nota de voz. Nesse caso escreva a fala em texto puro, sem HTML nem " <>
                       "emojis, porque vai ser lida por um sintetizador. Não descreva o áudio " <>
                       "('*áudio de 10s*'): escreva a fala de verdade."

  # Vocabulário curto em inglês: é o que o eleven_v3 documenta, e é o teto do
  # que os modelos Fish fora do drama-3 interpretam como direção
  @tag_instruction " Você PODE dirigir a entrega com audio tags entre colchetes no meio da " <>
                     "fala — [sarcastic], [laughs], [whispers], [sighs], [excited], " <>
                     "[mischievously] — pra variar o tom conforme a situação. Use com " <>
                     "parcimônia, no máximo uma ou duas por fala, e só quando somam à " <>
                     "interpretação."

  # O drama-3 aceita a direção escrita em qualquer idioma e em frase inteira,
  # então aqui ela sai em português e descrevendo a cena, não como etiqueta
  @drama_instruction " Você PODE dirigir a entrega escrevendo a direção em português entre " <>
                       "colchetes no meio da fala — [quase rindo], [sussurrando, fingindo " <>
                       "pena], [seco, sem paciência] — descrevendo emoção, intenção ou ritmo, " <>
                       "sem nenhum dígito dentro dos colchetes. Pode também marcar um trecho " <>
                       "curto com <whisper>, <emphasis>, <soft>, <fast>, <slow>, <stress> ou " <>
                       "<forceful>, sempre fechando a tag (<emphasis>agora</emphasis>). Use " <>
                       "com parcimônia, no máximo uma ou duas por fala, e só quando somam à " <>
                       "interpretação."

  @voice_instruction "\n\nSe a ocasião pedir uma voz diferente da sua padrão (personagem, " <>
                       "emoção marcante, imitação pedida no chat...), troque o marcador de " <>
                       "áudio por UM dos dois abaixo — nunca os dois juntos, nunca junto com " <>
                       "[[ratobo:audio]]:\n" <>
                       "— Pediram a voz de uma PESSOA ou PERSONAGEM específico e conhecido " <>
                       "(\"voz do fulano\", \"voz de tal personagem\")? " <>
                       "[[ratobo:voice:nome:nome da pessoa ou personagem]] — busca pelo nome " <>
                       "exato; só acha se existir alguém cadastrado com esse nome, senão volta " <>
                       "pra voz padrão sem avisar.\n" <>
                       "— Pediram um ESTILO sem nome específico (\"voz de mulher\", \"voz " <>
                       "grave\", \"voz de velho\")? [[ratobo:voice:estilo:palavra1 palavra2]] " <>
                       "usando SÓ palavras deste vocabulário fixo, quantas fizerem sentido: " <>
                       Enum.join(@style_words, ", ") <>
                       ". Nunca invente palavra fora dessa lista — fora dela a busca não acha " <>
                       "nada.\nUse qualquer um dos dois raramente, só quando a voz padrão " <>
                       "destoaria claramente do que foi pedido."

  @dialogue_instruction "\n\nPra DIÁLOGO com mais de uma voz no mesmo áudio (cena com dois " <>
                          "personagens, por exemplo), repita um marcador " <>
                          "[[ratobo:voice:nome:...]] ou [[ratobo:voice:estilo:...]] no início " <>
                          "de CADA fala, alternando conforme quem fala — inclusive a primeira " <>
                          "fala precisa vir com marcador, senão ela não entra no áudio. " <>
                          "Exemplo:\n" <>
                          "[[ratobo:voice:nome:Fulano]] Fala do Fulano aqui.\n" <>
                          "[[ratobo:voice:estilo:feminina agressiva]] Resposta da segunda voz " <>
                          "aqui.\n"

  @dialogue_supported "O provedor de voz ativo monta isso num áudio só, com as vozes " <>
                        "alternando de verdade."

  @bipolar_instruction "\n\nQuando pedirem o MODO BIPOLAR (\"responde em modo bipolar\", " <>
                         "\"modo bipolar com as vozes de fulano e beltrano\"), monte a cena " <>
                         "assim, que é mais simples do que marcar fala por fala:\n" <>
                         "1. Declare o elenco UMA vez, em uma linha própria, com os nomes " <>
                         "separados por vírgula: [[ratobo:bipolar:Silvio Santos, Faustão]]. " <>
                         "No máximo #{@max_cast} nomes; se pedirem mais, escolha os " <>
                         "#{@max_cast} que rendem mais piada. Se o nome de UM personagem tiver " <>
                         "vírgula ou \"e\" dentro dele (dupla, nome de programa), ponha esse " <>
                         "nome entre parênteses pra ele não ser lido como dois: " <>
                         "[[ratobo:bipolar:(Chico e Felipe), Galvão]] são DOIS personagens, o " <>
                         "primeiro chamado \"Chico e Felipe\".\n" <>
                         "2. Escreva as falas como roteiro, uma por linha, começando pelo nome " <>
                         "do elenco seguido de dois-pontos. Use o nome exatamente como " <>
                         "declarou no elenco. Exemplo:\n" <>
                         "[[ratobo:bipolar:Silvio Santos, Faustão]]\n" <>
                         "Silvio Santos: Olha só quem apareceu no meu auditório.\n" <>
                         "Faustão: Ô loco meu, tu tá maluco?\n" <>
                         "Silvio Santos: Para tudo!\n" <>
                         "Cada um pode falar quantas vezes quiser, em qualquer ordem. Não " <>
                         "escreva narração antes da primeira fala — ela não entra no áudio. " <>
                         "Não use [[ratobo:audio]] nem [[ratobo:voice:...]] junto: o elenco já " <>
                         "diz que a resposta é áudio. Se o pedido não citar nome nenhum, " <>
                         "invente personagens reconhecíveis que combinem com a piada."

  @dialogue_unsupported "O provedor de voz ativo não monta diálogo multi-voz: o áudio sai " <>
                          "inteiro numa voz só, a da primeira fala marcada — não é erro, é a " <>
                          "voz padrão cobrindo o resto."

  @doc """
  Instrução de pós-ações para o system prompt. Monta em runtime porque as
  partes de direção de voz dependem do provider/modelo de TTS configurado no
  SSM: o que o drama-3 interpreta como atuação, o eleven_v3 não, e vice-versa.

  O modo bipolar só é ensinado onde o provider monta várias vozes num áudio
  só — ensinar fora disso seria prometer uma cena que sairia em voz única.
  """
  def instruction do
    direction = if RuntimeEnvs.fish_drama?(), do: @drama_instruction, else: @tag_instruction

    dialogue =
      if RuntimeEnvs.tts_dialogue?(),
        do: @dialogue_supported <> @bipolar_instruction,
        else: @dialogue_unsupported

    @gif_instruction <>
      @audio_instruction <>
      direction <> @voice_instruction <> @dialogue_instruction <> dialogue
  end

  @doc "Separa o texto limpo das pós-ações sinalizadas nele"
  def extract(nil), do: {"", []}

  def extract(text) do
    actions =
      [{@gif_directive, :gif}, {@audio_directive, :audio}]
      |> Enum.filter(fn {directive, _action} -> Regex.match?(directive, text) end)
      |> Enum.map(fn {_directive, action} -> action end)
      |> add_voice_action(text)

    {strip(text), actions}
  end

  # [[ratobo:voice:...]] (qualquer um dos dois modos) implica áudio: some das
  # duas listas em vez de exigir que o modelo escreva [[ratobo:audio]] junto
  defp add_voice_action(actions, text) do
    cond do
      match = Regex.run(@voice_name_directive, text) ->
        [_, name] = match
        Enum.uniq([:audio, {:voice_name, String.trim(name)} | actions])

      match = Regex.run(@voice_style_directive, text) ->
        [_, style] = match
        Enum.uniq([:audio, {:voice_style, parse_style_words(style)} | actions])

      true ->
        actions
    end
  end

  # Só as palavras do vocabulário fixo sobrevivem — o resto é ruído que o
  # modelo eventualmente cola junto (artigo, pontuação) e não deve virar
  # filtro de busca
  defp parse_style_words(text) do
    text
    |> String.downcase()
    |> String.split(~r/[,\s]+/, trim: true)
    |> Enum.filter(&(&1 in @style_words))
  end

  @doc """
  Elenco do modo bipolar: os nomes declarados em [[ratobo:bipolar:A, B, C]],
  na ordem, sem repetição e no máximo #{@max_cast}.

  `[]` quando o marcador não existe ou não sobrou nome nenhum nele — e aí não
  há cena a montar, o texto segue como resposta comum.
  """
  def cast(nil), do: []

  def cast(text) do
    case Regex.run(@bipolar_directive, text) do
      [_, names] -> parse_cast(names)
      _ -> []
    end
  end

  # "A, B e C" e "A, B, e C" são como se escreve lista em português, e o modelo
  # escreve o elenco espelhando o pedido do usuário. Separar só por vírgula
  # deixava a conjunção colada no nome ("e Galvão"), que nunca casa com a fala
  # "Galvão:" nem acha voz na biblioteca. Dupla com "e" no nome (Chitãozinho e
  # Xororó) acaba virando dois personagens — troca aceitável, já que o caso
  # comum é conjunção.
  @cast_separator ~r/\s*,\s*(?:e\s+)?|\s+e\s+/iu

  # Escape do separador: parênteses marcam UM personagem só, mesmo com vírgula
  # ou "e" dentro do nome. "(Chico e Felipe)" é uma busca por "Chico e Felipe",
  # não duas — serve pra dupla, nome de programa, apelido composto, qualquer
  # grafia da biblioteca que contenha o separador.
  @protected_name ~r/\(\s*([^)]{1,80}?)\s*\)/u

  # Artigo e preposição que o modelo arrasta do pedido pro elenco: "as vozes DA
  # Bea e DA Patricia" vira [[ratobo:bipolar:Bea do Bras e da Patricia Poeta]].
  # "da Patricia Poeta" não acha voz nenhuma na biblioteca e nem casa com a
  # fala escrita "Patricia Poeta:". Só no começo do nome — o "do" de
  # "Bea do Bras" é parte dele e fica.
  @leading_article ~r/^(?:[ao]s?|d[aeo]s?)\s+/iu

  defp parse_cast(names) do
    {masked, protected} = mask_protected(names)

    masked
    |> String.split(@cast_separator, trim: true)
    |> Enum.map(&restore_protected(&1, protected))
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.replace(&1, @leading_article, ""))
    |> Enum.reject(&(normalize_name(&1) in ["", "e"]))
    |> Enum.uniq_by(&normalize_name/1)
    |> Enum.take(@max_cast)
  end

  # Troca cada grupo protegido por um marcador que o separador não quebra, pra
  # ele atravessar o split inteiro. \x00 não aparece em resposta de LLM e não
  # casa @cast_separator, então serve de marcador sem escapar nada.
  defp mask_protected(names) do
    protected = @protected_name |> Regex.scan(names) |> Enum.map(fn [_full, inner] -> inner end)

    masked =
      protected
      |> Enum.with_index()
      |> Enum.reduce(names, fn {_inner, index}, text ->
        Regex.replace(@protected_name, text, "\x00#{index}\x00", global: false)
      end)

    {masked, protected}
  end

  defp restore_protected(part, protected) do
    protected
    |> Enum.with_index()
    |> Enum.reduce(part, fn {inner, index}, acc ->
      String.replace(acc, "\x00#{index}\x00", inner)
    end)
  end

  @doc """
  Separa `text` em falas de roteiro ("Fulano: fala") atribuídas a `cast`.
  Devolve `%{name: nome_do_elenco, text: fala}`, com `name` sempre na grafia
  declarada no elenco — é ela que o chamador usa pra achar a voz já resolvida.

  Linha que não abre fala nova pertence à fala anterior, então personagem pode
  falar vários parágrafos. Texto antes da primeira fala reconhecida é
  descartado: é narração de enquadramento ("olha essa cena:"), não fala de
  ninguém.

  `[]` quando nada casa — o chamador trata como "não é cena" e segue o fluxo
  normal, em vez de mandar áudio vazio pro sintetizador.
  """
  def script_turns(nil, _cast), do: []
  def script_turns(_text, []), do: []

  def script_turns(text, cast) do
    # strip/1 antes de fatiar porque o marcador pode vir no fim da resposta,
    # como os outros [[ratobo:...]] do projeto. Ali ele cairia na última fala
    # como continuação e seria lido em voz alta pelo sintetizador.
    text
    |> strip()
    |> String.split("\n")
    |> Enum.reduce([], &absorb_line(&1, &2, cast))
    |> Enum.reverse()
    |> Enum.map(fn turn -> %{turn | text: String.trim(turn.text)} end)
    |> Enum.reject(&(&1.text == ""))
  end

  defp absorb_line(line, turns, cast) do
    case speaker_of(line, cast) do
      {name, said} -> [%{name: name, text: said} | turns]
      nil -> continue_turn(line, turns)
    end
  end

  # Antes da primeira fala não há a quem atribuir a linha, então ela cai fora
  defp continue_turn(_line, []), do: []

  defp continue_turn(line, [current | rest]) do
    [%{current | text: current.text <> "\n" <> line} | rest]
  end

  defp speaker_of(line, cast) do
    with [_, prefix, said] <- Regex.run(@script_line, line),
         name when not is_nil(name) <- match_cast(prefix, cast) do
      {name, said}
    else
      _ -> nil
    end
  end

  # O modelo abrevia o que declarou no elenco ("Silvio Santos" vira "Silvio:"),
  # então o primeiro nome também vale. Sem isso a fala viraria continuação da
  # anterior e sairia na voz errada.
  defp match_cast(prefix, cast) do
    normalized = normalize_name(prefix)

    Enum.find(cast, fn name ->
      canonical = normalize_name(name)
      canonical == normalized or first_name(canonical) == normalized
    end)
  end

  defp first_name(name), do: name |> String.split(" ", parts: 2) |> hd()

  # Acento e caixa não podem decidir de quem é a fala: o elenco vem do pedido
  # do usuário e as falas, da redação do modelo — raramente batem letra a letra.
  # Parênteses também somem porque o modelo repete o escape na fala
  # ("(Chico e Felipe): ...") depois de usá-lo no elenco.
  defp normalize_name(name) do
    name
    |> String.replace(~r/[()]/u, "")
    |> String.trim()
    # também no casamento, não só no elenco: o modelo erra dos dois lados, e
    # "da Patricia Poeta:" numa fala tem que achar a "Patricia Poeta" do elenco
    |> String.replace(@leading_article, "")
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
  end

  @doc """
  Separa `text` em falas de diálogo multi-voz: uma entrada por marcador
  [[ratobo:voice:nome/estilo:...]] encontrado, com o texto que vem depois dele
  (até o próximo marcador ou o fim). Texto antes do primeiro marcador é
  descartado — é o que sustenta a regra da instrução de marcar toda fala,
  inclusive a primeira.

  `[]` quando não há marcador nenhum (não é diálogo) ou só um (é o caso já
  coberto por extract/1 — troca de voz de uma fala só, não diálogo).
  """
  def voice_turns(nil), do: []

  def voice_turns(text) do
    case Regex.scan(@voice_turn_directive, text) do
      [] ->
        []

      matches ->
        [_preamble | segments] = Regex.split(@voice_turn_directive, text)

        matches
        |> Enum.zip(segments)
        |> Enum.map(fn {[_full, mode, value], segment} ->
          %{action: turn_action(mode, value), text: String.trim(segment)}
        end)
        |> Enum.reject(&(&1.text == ""))
    end
  end

  defp turn_action("nome", value), do: {:voice_name, String.trim(value)}
  defp turn_action("estilo", value), do: {:voice_style, parse_style_words(value)}

  @doc "Remove qualquer diretiva do texto, inclusive as desconhecidas"
  def strip(nil), do: ""

  def strip(text) do
    text
    |> String.replace(@any_directive, "")
    |> String.trim()
  end

  @doc """
  Remove do texto visível toda direção de entrega: a de colchete ([sarcastic],
  [quase rindo, fingindo pena]) e as tags prosódicas do drama-3.

  Use no que o usuário lê (legenda da nota de voz, fallback de texto); o texto
  enviado ao sintetizador mantém as duas, que é como ele modula a entrega.
  """
  def strip_audio_tags(nil), do: ""

  def strip_audio_tags(text) do
    text
    |> String.replace(@audio_tag, "")
    |> String.replace(@prosody_tag, "")
    # Tag no meio da frase deixa espaço duplo; colapsa sem tocar em quebras de linha
    |> String.replace(~r/[ \t]{2,}/, " ")
    |> String.replace(~r/ +\n/, "\n")
    |> String.trim()
  end

  @doc """
  Prepara `text` pro sintetizador: tira o HTML do Telegram, mas preserva as
  tags prosódicas do drama-3 — elas também vêm entre `<>` e seriam varridas
  junto com o `<b>`, perdendo a direção antes de chegar na API.
  """
  def speech_text(nil), do: ""

  def speech_text(text) do
    text
    |> String.replace(~r/<[^>]+>/, &keep_prosody/1)
    |> String.trim()
  end

  defp keep_prosody(tag) do
    if Regex.match?(@prosody_tag, tag), do: tag, else: ""
  end
end
