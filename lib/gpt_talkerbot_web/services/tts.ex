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

    audio_or_error(Tesla.post(client, "/audio/speech", body))
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

      audio_or_error(Tesla.post(client, url, body))
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

      audio_or_error(Tesla.post(client, "/tts", body))
    end
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
  # decodifica e o corpo chega como binário cru
  defp audio_or_error({:ok, %{status: 200, body: audio}}) when is_binary(audio) and audio != "",
    do: {:ok, audio}

  defp audio_or_error(_), do: {:error, :unavailable}
end
