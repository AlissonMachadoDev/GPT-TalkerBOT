defmodule GptTalkerbotWeb.Services.VoiceSearch do
  @moduledoc """
  Busca dinâmica de voz na Voice Library do provedor de TTS ativo, a partir
  dos marcadores [[ratobo:voice:nome:...]] (busca por título/nome exato) e
  [[ratobo:voice:estilo:...]] (busca por vocabulário fixo — ver
  PostActions.style_words/0).

  Texto livre não serve de filtro em nenhum dos dois provedores: Fish `title`
  é substring contra o nome cadastrado do modelo, e `tag` é a label que o
  criador colocou nele — nenhum dos dois entende frase de humor. Por isso o
  modo "estilo" traduz um vocabulário fixo pros parâmetros reais de cada
  provedor em vez de mandar a frase do modelo direto pra busca.

  Só Fish Audio e ElevenLabs têm biblioteca pesquisável por API; a voz da
  OpenAI é fixa (@openai_voice em TTS), então find_voice/1 não busca nada
  pra ela — a síntese segue com a voz default configurada.
  """

  use Tesla

  require Logger

  alias GptTalkerbot.RuntimeEnvs

  # PT-BR -> parâmetro real de cada provedor. Os valores da ElevenLabs seguem
  # a convenção usual da label (male/female, young/middle_aged/old) — a doc
  # pública não lista o enum exato, então isso é o melhor palpite, a validar
  # em uso real. Os tags da Fish são folksonomia (o criador do modelo escolhe
  # livremente), então "grave"/"doce"/etc são um chute ainda mais best-effort;
  # gênero e idade têm bem mais chance de bater com tag cadastrada de verdade.
  @style_map %{
    "feminina" => %{fish: "female", elevenlabs: {:gender, "female"}},
    "masculina" => %{fish: "male", elevenlabs: {:gender, "male"}},
    "jovem" => %{fish: "young", elevenlabs: {:age, "young"}},
    "adulta" => %{fish: "middle_aged", elevenlabs: {:age, "middle_aged"}},
    "idosa" => %{fish: "elder", elevenlabs: {:age, "old"}},
    "grave" => %{fish: "deep", elevenlabs: nil},
    "doce" => %{fish: "sweet", elevenlabs: nil},
    "agressiva" => %{fish: "aggressive", elevenlabs: nil},
    "debochada" => %{fish: "sarcastic", elevenlabs: nil}
  }

  @doc """
  Acha o voice_id/reference_id mais parecido com a ação de voz extraída por
  PostActions (`{:voice_name, nome}` ou `{:voice_style, palavras}`).
  `{:ok, id}` ou `:error` (provider sem busca, sem api_key, sem palavra
  reconhecida ou chamada malsucedida) — o chamador cai pra voz default nesse caso.
  """
  def find_voice({:voice_name, name}) when is_binary(name) do
    dispatch(&name_query/2, name)
  end

  def find_voice({:voice_style, words}) when is_list(words) do
    dispatch(&style_query/2, words)
  end

  def find_voice(_), do: :error

  defp dispatch(query_fun, arg) do
    case RuntimeEnvs.get_tts_provider() do
      :fish -> run_fish(query_fun.(:fish, arg))
      :elevenlabs -> run_elevenlabs(query_fun.(:elevenlabs, arg))
      _ -> :error
    end
  end

  defp name_query(:fish, name), do: [title: name]
  defp name_query(:elevenlabs, name), do: [search: name]

  defp style_query(:fish, words) do
    case style_values(words, :fish) do
      [] -> nil
      tags -> [tag: Enum.join(tags, ",")]
    end
  end

  defp style_query(:elevenlabs, words) do
    case style_values(words, :elevenlabs) do
      [] -> nil
      pairs -> Enum.uniq_by(pairs, &elem(&1, 0))
    end
  end

  defp style_values(words, provider) do
    words
    |> Enum.map(&get_in(@style_map, [&1, provider]))
    |> Enum.reject(&is_nil/1)
  end

  defp run_fish(nil), do: :error

  defp run_fish(extra_query) do
    key = RuntimeEnvs.get_fish_api_key()

    if key == "" do
      :error
    else
      query = extra_query ++ [page_size: 1, sort_by: "score"]

      fish_client(key)
      |> Tesla.get("/model", query: query)
      |> handle_result(["items", Access.at(0), "_id"], "fish", extra_query)
    end
  end

  defp run_elevenlabs(nil), do: :error

  defp run_elevenlabs(extra_query) do
    key = RuntimeEnvs.get_elevenlabs_api_key()

    if key == "" do
      :error
    else
      query = extra_query ++ [page_size: 1]

      elevenlabs_client(key)
      |> Tesla.get("/v2/voices", query: query)
      |> handle_result(["voices", Access.at(0), "voice_id"], "elevenlabs", extra_query)
    end
  end

  defp handle_result({:ok, %{status: 200, body: body}}, path, provider, query) do
    case get_in(body, path) do
      id when is_binary(id) and id != "" ->
        {:ok, id}

      _ ->
        Logger.warning("VoiceSearch: #{provider} sem resultado pra #{inspect(query)}")
        :error
    end
  end

  defp handle_result(result, _path, provider, query) do
    Logger.warning("VoiceSearch: #{provider} falhou pra #{inspect(query)}: #{inspect(result)}")
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
