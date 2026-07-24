defmodule GptTalkerbotWeb.Services.TTS do
  @moduledoc """
  Síntese de voz. Recebe texto puro e devolve os bytes do áudio em Ogg/Opus,
  prontos para o sendVoice do Telegram.

  Provider selecionável via RuntimeEnvs (tts_provider): `openai` (padrão) ou
  `elevenlabs`. ElevenLabs exige api_key + voice_id configurados; sem eles, cai
  automaticamente pro OpenAI.
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

  @doc """
  Sintetiza `text` em áudio. Retorna `{:ok, binary}` (Ogg/Opus) ou
  `{:error, reason}`.
  """
  def synthesize(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:error, :empty_text}
      trimmed -> trimmed |> String.slice(0, @max_chars) |> dispatch()
    end
  end

  defp dispatch(text) do
    case RuntimeEnvs.get_tts_provider() do
      :elevenlabs -> elevenlabs(text)
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

  defp elevenlabs(text) do
    key = RuntimeEnvs.get_elevenlabs_api_key()
    voice = RuntimeEnvs.get_elevenlabs_voice("default")

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

  # A resposta 200 vem com content-type de áudio: o JSON middleware não a
  # decodifica e o corpo chega como binário cru
  defp audio_or_error({:ok, %{status: 200, body: audio}}) when is_binary(audio) and audio != "",
    do: {:ok, audio}

  defp audio_or_error(_), do: {:error, :unavailable}
end
