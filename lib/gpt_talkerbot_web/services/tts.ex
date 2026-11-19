defmodule GptTalkerbotWeb.Services.TTS do
  @moduledoc """
  Síntese de voz. Recebe texto puro e devolve os bytes do áudio em Ogg/Opus,
  prontos para o sendVoice do Telegram.

  Provider selecionável via RuntimeEnvs (tts_provider): `openai` (padrão),
  `elevenlabs` ou `fish`. ElevenLabs e Fish exigem api_key + voice_id
  configurados; sem eles, cai automaticamente pro OpenAI.
  """

  use Tesla

  require Logger

  alias GptTalkerbot.RuntimeEnvs

  # A OpenAI corta em 4096 chars; abaixo disso por custo e porque nota de voz
  # longa não combina com o tom do bot
  @max_chars 1500

  @openai_model "gpt-4o-mini-tts"
  @openai_voice "onyx"
  @openai_format "opus"

  # Ogg/Opus, o container que o sendVoice do Telegram espera
  @elevenlabs_output_format "opus_48000_64"

  @fish_output_format "opus"

  # Teto documentado do text-to-dialogue: a ElevenLabs pede no máximo 2000
  # caracteres somando todos os inputs[].text, e avisa que acima disso a
  # requisição pode truncar no streaming ou voltar erro de validação.
  @elevenlabs_dialogue_max_chars 2000

  # A Fish não publica teto no /v1/tts, então aqui o corte é de custo, não de
  # limite técnico — ela cobra por byte UTF-8 de entrada. Folga sobre a
  # ElevenLabs porque o provider aguenta cena maior.
  @fish_dialogue_max_chars 4000

  @doc """
  Sintetiza `text` em áudio. Retorna `{:ok, binary}` (Ogg/Opus) ou
  `{:error, reason}`.

  `voice_override`, quando informado, substitui a voz "default" configurada
  (usado pela busca dinâmica de voz — ver VoiceSearch). Ignorado no provider
  OpenAI, que não tem biblioteca de vozes pesquisável.
  """
  def synthesize(text, voice_override \\ nil) when is_binary(text) do
    case String.trim(text) do
      "" -> {:error, :empty_text}
      trimmed -> trimmed |> String.slice(0, @max_chars) |> dispatch(voice_override)
    end
  end

  defp dispatch(text, voice_override) do
    case RuntimeEnvs.get_tts_provider() do
      :elevenlabs -> elevenlabs(text, voice_override)
      :fish -> fish(text, voice_override)
      :openai -> openai(text)
    end
  end

  # --- OpenAI ---

  defp openai(text) do
    client = openai_client(RuntimeEnvs.get_openai_api_key())

    body = %{
      "model" => @openai_model,
      "voice" => @openai_voice,
      "input" => text,
      "response_format" => @openai_format
    }

    audio_or_error(Tesla.post(client, "/audio/speech", body), "openai")
  end

  defp openai_client(api_key) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      Tesla.Middleware.JSON,
      # debug: false porque a resposta é áudio binário e o dump de debug do
      # logger quebra ao formatar bytes não-UTF8 como texto
      {Tesla.Middleware.Logger, level: :warning, debug: false}
    ])
  end

  # --- ElevenLabs ---

  defp elevenlabs(text, voice_override) do
    key = RuntimeEnvs.get_elevenlabs_api_key()
    voice = voice_override || RuntimeEnvs.get_elevenlabs_voice("default")

    if key == "" or voice == "" do
      Logger.warning("TTS: elevenlabs selecionado sem api_key/voz default; usando OpenAI")
      openai(text)
    else
      client = elevenlabs_client(key)
      url = "/text-to-speech/#{voice}?output_format=#{@elevenlabs_output_format}"

      body = %{
        "text" => text,
        "model_id" => RuntimeEnvs.get_elevenlabs_model(),
        "voice_settings" => RuntimeEnvs.get_elevenlabs_voice_settings()
      }

      audio_or_error(Tesla.post(client, url, body), "elevenlabs")
    end
  end

  defp elevenlabs_client(api_key) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "https://api.elevenlabs.io/v1"},
      {Tesla.Middleware.Headers, [{"xi-api-key", api_key}]},
      Tesla.Middleware.JSON,
      # debug: false porque a resposta é áudio binário e o dump de debug do
      # logger quebra ao formatar bytes não-UTF8 como texto
      {Tesla.Middleware.Logger, level: :warning, debug: false}
    ])
  end

  @doc """
  Sintetiza um diálogo com várias vozes num áudio só. `turns` é uma lista de
  `%{text: ..., voice_id: ...}`, uma entrada por fala.

  Dois caminhos: text-to-dialogue da ElevenLabs (até 10 vozes distintas) e a
  Fish no drama-3, que aceita `reference_id` em array e indexa as falas com
  marcadores `<|speaker:N|>`. Nos demais — inclusive a Fish fora do drama-3,
  que leria os marcadores como texto — devolve `{:error, :unsupported}`.

  Cena comprida é cortada na última fala que couber no orçamento do provider
  (ver trim_to_budget/2) — melhor uma cena curta do que a última fala cortada
  no meio da palavra.

  Sem fallback automático pro OpenAI: um erro aqui significa "sem diálogo
  mesmo", e quem chama decide se cai pra síntese de voz única ou pra texto.
  """
  def synthesize_dialogue(turns) when is_list(turns) and turns != [] do
    cond do
      not RuntimeEnvs.tts_dialogue?() ->
        Logger.warning(
          "TTS: cena de #{length(turns)} falas recusada — provider=" <>
            "#{RuntimeEnvs.get_tts_provider()} fish_model=#{RuntimeEnvs.get_fish_model()} " <>
            "não monta multi-voz (precisa elevenlabs, ou fish no drama-3)"
        )

        {:error, :unsupported}

      # Voz vazia é o que sobra quando a busca não acha nada e nem a "default"
      # está configurada. A ElevenLabs recusaria o input e a Fish montaria um
      # reference_id furado — falhar aqui dá um erro legível no log.
      Enum.any?(turns, &(&1.voice_id in [nil, ""])) ->
        Logger.warning(
          "TTS: cena recusada — fala sem voz resolvida e sem voz default configurada"
        )

        {:error, :no_voice}

      true ->
        dialogue(turns)
    end
  end

  defp dialogue(turns) do
    case RuntimeEnvs.get_tts_provider() do
      :elevenlabs ->
        turns |> trim_to_budget(@elevenlabs_dialogue_max_chars) |> elevenlabs_dialogue()

      :fish ->
        turns |> trim_to_budget(@fish_dialogue_max_chars) |> fish_dialogue()
    end
  end

  @doc """
  Descarta falas do fim da cena até o total caber em `budget` caracteres.

  A fala é a unidade: cortar no meio dela deixaria o personagem mudo na
  metade da frase. A exceção é a primeira — se ela sozinha já estoura o
  orçamento, aí sim é truncada, porque devolver cena vazia seria pior.
  """
  def trim_to_budget(turns, budget) do
    {kept, _used} = Enum.reduce_while(turns, {[], 0}, &take_while_fits(&1, &2, budget))
    kept = Enum.reverse(kept)

    if length(kept) < length(turns) do
      Logger.warning(
        "TTS: cena cortada de #{length(turns)} pra #{length(kept)} falas (orçamento #{budget} chars)"
      )
    end

    kept
  end

  defp take_while_fits(turn, {acc, used}, budget) do
    size = String.length(turn.text)

    cond do
      acc == [] and size > budget ->
        {:halt, {[%{turn | text: String.slice(turn.text, 0, budget)}], budget}}

      used + size > budget ->
        {:halt, {acc, used}}

      true ->
        {:cont, {[turn | acc], used + size}}
    end
  end

  defp elevenlabs_dialogue(turns) do
    key = RuntimeEnvs.get_elevenlabs_api_key()

    if key == "" do
      {:error, :no_api_key}
    else
      inputs = Enum.map(turns, &%{"text" => &1.text, "voice_id" => &1.voice_id})
      client = elevenlabs_client(key)
      url = "/text-to-dialogue?output_format=#{@elevenlabs_output_format}"
      body = %{"inputs" => inputs, "model_id" => RuntimeEnvs.get_elevenlabs_model()}

      log_dialogue_request("elevenlabs/dialogue", turns, RuntimeEnvs.get_elevenlabs_model())
      audio_or_error(Tesla.post(client, url, body), "elevenlabs/dialogue")
    end
  end

  # O número de vozes DISTINTAS é o que diz se a cena vai sair como cena: com
  # 1 voz e 4 falas o áudio é monólogo, e esse era o sintoma invisível no log.
  defp log_dialogue_request(label, turns, model) do
    vozes = turns |> Enum.map(& &1.voice_id) |> Enum.uniq()
    chars = turns |> Enum.map(&String.length(&1.text)) |> Enum.sum()

    Logger.info(
      "TTS[#{label}]: modelo=#{model} falas=#{length(turns)} " <>
        "vozes_distintas=#{length(vozes)} chars=#{chars} vozes=#{inspect(vozes)}"
    )

    if length(vozes) == 1 and length(turns) > 1 do
      Logger.warning(
        "TTS[#{label}]: #{length(turns)} falas com UMA voz só — o áudio vai sair em monólogo"
      )
    end
  end

  # --- Fish Audio ---

  defp fish(text, voice_override) do
    key = RuntimeEnvs.get_fish_api_key()
    voice = voice_override || RuntimeEnvs.get_fish_voice("default")

    if key == "" or voice == "" do
      Logger.warning("TTS: fish selecionado sem api_key/voz default; usando OpenAI")
      openai(text)
    else
      client = fish_client(key)

      body = %{
        "text" => text,
        "reference_id" => voice,
        "format" => @fish_output_format
      }

      audio_or_error(Tesla.post(client, "/tts", body), "fish")
    end
  end

  defp fish_dialogue(turns) do
    key = RuntimeEnvs.get_fish_api_key()

    if key == "" do
      {:error, :no_api_key}
    else
      body = build_fish_dialogue_body(turns)
      log_dialogue_request("fish/dialogue", turns, RuntimeEnvs.get_fish_model())
      # O texto vai inteiro no log porque é onde se vê se os marcadores
      # <|speaker:N|> saíram alternando ou se todos viraram speaker:0
      Logger.info("TTS[fish/dialogue]: text=#{inspect(body["text"], printable_limit: 600)}")

      audio_or_error(Tesla.post(fish_client(key), "/tts", body), "fish/dialogue")
    end
  end

  @doc """
  Monta o corpo do /tts multi-voz da Fish: as vozes viram o array
  `reference_id` e cada fala é prefixada pelo marcador `<|speaker:N|>`, onde N
  é a posição da voz nesse array.

  Como o índice é posicional, personagem que fala mais de uma vez precisa
  colapsar numa entrada só — daí a deduplicação por ordem de aparição.
  """
  def build_fish_dialogue_body(turns) do
    voices = turns |> Enum.map(& &1.voice_id) |> Enum.uniq()
    index_of = voices |> Enum.with_index() |> Map.new()

    text =
      Enum.map_join(turns, fn %{text: text, voice_id: voice} ->
        "<|speaker:#{index_of[voice]}|>#{text}"
      end)

    %{
      "text" => text,
      "reference_id" => voices,
      "format" => @fish_output_format
    }
  end

  defp fish_client(api_key) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "https://api.fish.audio/v1"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      {Tesla.Middleware.Headers, [{"model", RuntimeEnvs.get_fish_model()}]},
      Tesla.Middleware.JSON,
      # debug: false porque a resposta é áudio binário e o dump de debug do
      # logger quebra ao formatar bytes não-UTF8 como texto
      {Tesla.Middleware.Logger, level: :warning, debug: false}
    ])
  end

  # A resposta 200 vem com content-type de áudio: o JSON middleware não a
  # decodifica e o corpo chega como binário cru. `label` diz qual chamada foi,
  # porque são cinco (openai, elevenlabs, elevenlabs/dialogue, fish,
  # fish/dialogue) e no log elas eram indistinguíveis.
  defp audio_or_error({:ok, %{status: 200, body: audio}}, label)
       when is_binary(audio) and audio != "" do
    Logger.info("TTS[#{label}]: 200, #{byte_size(audio)} bytes de áudio")
    {:ok, audio}
  end

  # O corpo do erro é onde a API explica o que recusou — voz inexistente,
  # modelo que não aceita array em reference_id, texto grande demais. Sem
  # logá-lo todo problema vira o mesmo :unavailable opaco.
  defp audio_or_error({:ok, %{status: status, body: body}}, label) do
    Logger.warning("TTS[#{label}]: HTTP #{status} — #{describe_body(body)}")
    {:error, {:http, status}}
  end

  defp audio_or_error({:error, reason}, label) do
    Logger.warning("TTS[#{label}]: falha de transporte — #{inspect(reason)}")
    {:error, :unavailable}
  end

  defp audio_or_error(other, label) do
    Logger.warning("TTS[#{label}]: resposta inesperada — #{inspect(other, limit: 5)}")
    {:error, :unavailable}
  end

  # inspect/2 em vez de String.slice porque o corpo do erro pode vir como mapa
  # JSON decodificado ou como binário não-UTF8, e slice quebraria no segundo
  defp describe_body(body), do: inspect(body, limit: 20, printable_limit: 400)
end
