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

  @any_directive ~r/\[\[\s*ratobo:[^\]]{0,60}\]\]/iu

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

  @dialogue_unsupported "O provedor de voz ativo não monta diálogo multi-voz: o áudio sai " <>
                          "inteiro numa voz só, a da primeira fala marcada — não é erro, é a " <>
                          "voz padrão cobrindo o resto."

  @doc """
  Instrução de pós-ações para o system prompt. Monta em runtime porque as
  partes de direção de voz dependem do provider/modelo de TTS configurado no
  SSM: o que o drama-3 interpreta como atuação, o eleven_v3 não, e vice-versa.
  """
  def instruction do
    direction = if RuntimeEnvs.fish_drama?(), do: @drama_instruction, else: @tag_instruction

    dialogue =
      if RuntimeEnvs.tts_dialogue?(), do: @dialogue_supported, else: @dialogue_unsupported

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
