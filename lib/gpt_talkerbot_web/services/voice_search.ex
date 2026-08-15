defmodule GptTalkerbotWeb.Services.VoiceSearch do
  @moduledoc """
  Busca dinâmica de voz na Voice Library do provedor de TTS ativo, a partir de
  uma descrição livre escrita pelo modelo (marcador [[ratobo:voice:descrição]]).

  Só Fish Audio e ElevenLabs têm biblioteca pesquisável por API; a voz da
  OpenAI é fixa (@openai_voice em TTS), então find_voice/1 não busca nada
  pra ela — a síntese segue com a voz default configurada.
  """

  use Tesla

  require Logger

  alias GptTalkerbot.RuntimeEnvs

  @doc """
  Acha o voice_id/reference_id mais parecido com `description` na biblioteca
  do provider ativo. `{:ok, id}` ou `:error` (provider sem busca, sem api_key
  ou chamada malsucedida) — o chamador cai pra voz default nesse caso.
  """
  def find_voice(description) when is_binary(description) do
    case RuntimeEnvs.get_tts_provider() do
      :fish -> search_fish(description)
      :elevenlabs -> search_elevenlabs(description)
      _ -> :error
    end
  end

  defp search_fish(description) do
    key = RuntimeEnvs.get_fish_api_key()

    if key == "" do
      :error
    else
      client = fish_client(key)
      query = [title: description, page_size: 1, sort_by: "score"]

      client
      |> Tesla.get("/model", query: query)
      |> handle_result(["items", Access.at(0), "_id"], "fish", description)
    end
  end

  defp search_elevenlabs(description) do
    key = RuntimeEnvs.get_elevenlabs_api_key()

    if key == "" do
      :error
    else
      client = elevenlabs_client(key)
      query = [search: description, page_size: 1]

      client
      |> Tesla.get("/v2/voices", query: query)
      |> handle_result(["voices", Access.at(0), "voice_id"], "elevenlabs", description)
    end
  end

  defp handle_result({:ok, %{status: 200, body: body}}, path, provider, description) do
    case get_in(body, path) do
      id when is_binary(id) and id != "" ->
        {:ok, id}

      _ ->
        Logger.warning("VoiceSearch: #{provider} sem resultado pra #{inspect(description)}")
        :error
    end
  end

  defp handle_result(result, _path, provider, description) do
    Logger.warning(
      "VoiceSearch: #{provider} falhou pra #{inspect(description)}: #{inspect(result)}"
    )

    :error
  end

  defp fish_client(api_key) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "https://api.fish.audio"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, level: :warning}
    ])
  end

  defp elevenlabs_client(api_key) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "https://api.elevenlabs.io"},
      {Tesla.Middleware.Headers, [{"xi-api-key", api_key}]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, level: :warning}
    ])
  end
end
