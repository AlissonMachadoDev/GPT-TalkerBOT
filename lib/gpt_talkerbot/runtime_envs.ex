defmodule GptTalkerbot.RuntimeEnvs do
  @moduledoc """
  Configuração de runtime do bot.

  Um GenServer busca os parâmetros no AWS SSM (path /gpt_talkerbot/prod/*)
  na inicialização e a cada 12h, e publica o resultado em :persistent_term.
  As leituras (várias por mensagem processada) não passam pelo processo —
  são lookups diretos no persistent_term, sem gargalo de serialização.
  """

  use GenServer

  require Logger

  @refresh_interval_ms 12 * 60 * 60 * 1_000
  @ssm_prefix "/gpt_talkerbot/prod/"

  @defaults %{
    openai_api_key: "",
    grok_api_key: "",
    telegram_webhook_secret: "",
    using: :grok,
    spice_threshold: 0.35,
    # Acima de ~1.0 o Grok degenera em salada de tokens em respostas longas
    # (incidente de 16/07/2026); o SSM pode ajustar, mas o default é seguro
    temperature: 0.9,
    user_labels: %{},
    default_prompt: "",
    owner_id: "",
    allowed_groups: [],
    allowed_users: [],
    grok_reasoning: "low",
    openai_model: "gpt-5.4-mini",
    grok_model: "grok-4.5",
    # TTS: provider selecionável (openai | elevenlabs). ElevenLabs exige
    # api_key + ao menos a voz "default"; sem eles o TTS cai pro OpenAI.
    tts_provider: "openai",
    elevenlabs_api_key: "",
    # Mapa nome->voice_id (formato "default:<id>;male_1:<id>"), pra escolher a
    # voz por contexto. Por ora só a "default" é usada.
    elevenlabs_voices: %{},
    elevenlabs_model: "eleven_multilingual_v2",
    relevance_threshold: 0.4,
    always_include_last: 4,
    max_context_messages: 20,
    session_gap_minutes: 60,
    interject_probability: 0.03,
    interject_cooldown_minutes: 30,
    reaction_probability: 0.05,
    gif_probability: 0.02,
    daily_summary_hour: 23,
    utc_offset: -3
  }

  # mood_duration foi removido: o humor agora é sorteado por tempo (a cada 6h)
  # no MoodTracker, sem contagem de respostas.

  @float_params [
    :spice_threshold,
    :temperature,
    :relevance_threshold,
    :interject_probability,
    :reaction_probability,
    :gif_probability
  ]
  @integer_params [
    :always_include_last,
    :max_context_messages,
    :session_gap_minutes,
    :interject_cooldown_minutes,
    :daily_summary_hour,
    :utc_offset
  ]
  @string_params [
    :default_prompt,
    :owner_id,
    :grok_reasoning,
    :openai_model,
    :grok_model,
    :telegram_webhook_secret,
    :tts_provider,
    :elevenlabs_model
  ]
  @integer_list_params [:allowed_groups, :allowed_users]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state =
      @defaults
      |> Map.merge(%{
        openai_api_key: Application.get_env(:gpt_talkerbot, :openai_api_key, ""),
        grok_api_key: Application.get_env(:gpt_talkerbot, :grok_api_key, ""),
        elevenlabs_api_key: Application.get_env(:gpt_talkerbot, :elevenlabs_api_key, ""),
        telegram_webhook_secret:
          Application.get_env(
            :gpt_talkerbot,
            :telegram_webhook_secret,
            @defaults.telegram_webhook_secret
          ),
        default_prompt:
          Application.get_env(:gpt_talkerbot, :default_prompt, @defaults.default_prompt),
        owner_id: Application.get_env(:gpt_talkerbot, :owner_id, @defaults.owner_id),
        allowed_groups:
          Application.get_env(:gpt_talkerbot, :allowed_groups, @defaults.allowed_groups),
        allowed_users:
          Application.get_env(:gpt_talkerbot, :allowed_users, @defaults.allowed_users),
        # tts_provider e elevenlabs_voices normalmente vêm do SSM; em dev (SSM
        # off) esse override permite configurá-los pelo dev.secret.exs
        tts_provider:
          Application.get_env(:gpt_talkerbot, :tts_provider, @defaults.tts_provider),
        elevenlabs_voices:
          normalize_voices(
            Application.get_env(:gpt_talkerbot, :elevenlabs_voices, @defaults.elevenlabs_voices)
          )
      })
      |> fetch_variables()

    publish(state)
    schedule_refresh()
    {:ok, state}
  end

  # --- Leitura (persistent_term, sem passar pelo GenServer) ---

  def get_current_service, do: get(:using)
  def get_openai_api_key, do: get(:openai_api_key)
  def get_grok_api_key, do: get(:grok_api_key)
  def get_telegram_webhook_secret, do: get(:telegram_webhook_secret)
  def get_spice_threshold, do: get(:spice_threshold)
  def get_temperature, do: get(:temperature)
  def get_user_labels, do: get(:user_labels)
  def get_default_prompt, do: get(:default_prompt)
  def get_owner_id, do: get(:owner_id)
  def get_allowed_groups, do: get(:allowed_groups)
  def get_allowed_users, do: get(:allowed_users)
  def get_grok_reasoning, do: get(:grok_reasoning)
  def get_openai_model, do: get(:openai_model)
  def get_grok_model, do: get(:grok_model)
  def get_tts_provider, do: normalize_tts_provider(get(:tts_provider))
  def get_elevenlabs_api_key, do: get(:elevenlabs_api_key)
  def get_elevenlabs_model, do: get(:elevenlabs_model)
  def get_elevenlabs_voices, do: get(:elevenlabs_voices)

  @doc """
  Voice_id da ElevenLabs para o contexto `name` (default "default"). Cai na voz
  "default" se o nome não existir, ou "" se nem a default estiver configurada.
  """
  def get_elevenlabs_voice(name \\ "default"), do: resolve_voice(get_elevenlabs_voices(), name)

  @doc false
  def resolve_voice(voices, name) do
    Map.get(voices, name) || Map.get(voices, "default") || ""
  end

  @doc false
  def normalize_tts_provider(value) do
    case value do
      :elevenlabs -> :elevenlabs
      "elevenlabs" -> :elevenlabs
      _ -> :openai
    end
  end
  def get_relevance_threshold, do: get(:relevance_threshold)
  def get_always_include_last, do: get(:always_include_last)
  def get_max_context_messages, do: get(:max_context_messages)
  def get_session_gap_minutes, do: get(:session_gap_minutes)
  def get_interject_probability, do: get(:interject_probability)
  def get_interject_cooldown_minutes, do: get(:interject_cooldown_minutes)
  def get_reaction_probability, do: get(:reaction_probability)
  def get_gif_probability, do: get(:gif_probability)
  def get_daily_summary_hour, do: get(:daily_summary_hour)
  def get_utc_offset, do: get(:utc_offset)

  defp get(key) do
    :persistent_term.get(__MODULE__, @defaults) |> Map.get(key, Map.get(@defaults, key))
  end

  # --- Inspeção ---

  @secret_params [:openai_api_key, :grok_api_key, :elevenlabs_api_key, :telegram_webhook_secret]

  @doc """
  Snapshot das variáveis em vigor, com segredos mascarados e o prompt
  resumido para tamanho — seguro para logar ou mandar no chat do owner.
  """
  def dump do
    :persistent_term.get(__MODULE__, @defaults)
    |> Map.new(fn {key, value} -> {key, printable(key, value)} end)
  end

  @doc "dump/0 formatado em texto, uma variável por linha, em ordem alfabética"
  def format_dump do
    dump()
    |> Enum.sort()
    |> Enum.map_join("\n", fn {key, value} -> "#{key}: #{value}" end)
  end

  defp printable(key, value) when key in @secret_params do
    case value do
      "" -> "(vazia)"
      v -> "definida (#{String.length(v)} chars)"
    end
  end

  defp printable(:default_prompt, ""), do: "(vazio)"
  defp printable(:default_prompt, v), do: "(#{String.length(v)} chars)"
  defp printable(_key, value) when is_binary(value), do: value
  defp printable(_key, value), do: inspect(value)

  # --- Escrita ---

  def set_current_service(service) when service in [:openai, :grok] do
    GenServer.cast(__MODULE__, {:set_current_service, service})
  end

  def update_variables, do: GenServer.cast(__MODULE__, :update_variables)

  @impl true
  def handle_cast({:set_current_service, service}, state) do
    new_state = %{state | using: service}
    publish(new_state)
    {:noreply, new_state}
  end

  def handle_cast(:update_variables, state) do
    new_state = fetch_variables(state)
    publish(new_state)

    Logger.info(
      "RuntimeEnvs: variables updated (spice_threshold=#{new_state.spice_threshold}, temperature=#{new_state.temperature})"
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refresh_variables, state) do
    new_state = fetch_variables(state)
    publish(new_state)

    Logger.info(
      "RuntimeEnvs: scheduled refresh (spice_threshold=#{new_state.spice_threshold}, temperature=#{new_state.temperature})"
    )

    schedule_refresh()
    {:noreply, new_state}
  end

  defp publish(state), do: :persistent_term.put(__MODULE__, state)

  defp schedule_refresh do
    Process.send_after(self(), :refresh_variables, @refresh_interval_ms)
  end

  # --- Fetch do SSM ---

  defp fetch_variables(state) do
    if Application.get_env(:gpt_talkerbot, :ssm_enabled, true) do
      state
      |> fetch_typed(@float_params, &parse_float/2)
      |> fetch_typed(@integer_params, &parse_integer/2)
      |> fetch_typed(@string_params, fn value, _fallback -> value end)
      |> fetch_typed(@integer_list_params, &parse_integer_list/2)
      |> Map.put(:user_labels, fetch_user_labels(state.user_labels))
      |> Map.put(:elevenlabs_voices, fetch_elevenlabs_voices(state.elevenlabs_voices))
    else
      state
    end
  end

  defp fetch_typed(state, keys, parser) do
    Enum.reduce(keys, state, fn key, acc ->
      fallback = Map.get(acc, key)

      value =
        case fetch_raw_param(@ssm_prefix <> to_string(key)) do
          {:ok, raw} -> parser.(raw, fallback)
          :error -> fallback
        end

      Map.put(acc, key, value)
    end)
  end

  defp fetch_raw_param(param_name) do
    try do
      param_name
      |> ExAws.SSM.get_parameter(with_decryption: true)
      |> ExAws.request()
      |> case do
        {:ok, %{"Parameter" => %{"Value" => value}}} ->
          {:ok, value}

        {:error, reason} ->
          Logger.warning(
            "RuntimeEnvs: failed to fetch #{param_name} from SSM: #{inspect(reason)}"
          )

          :error
      end
    rescue
      e ->
        Logger.warning(
          "RuntimeEnvs: exception fetching #{param_name} from SSM: #{Exception.message(e)}"
        )

        :error
    catch
      :exit, reason ->
        Logger.warning("RuntimeEnvs: exit fetching #{param_name} from SSM: #{inspect(reason)}")
        :error
    end
  end

  defp parse_float(value, fallback) do
    case Float.parse(value) do
      {f, _} ->
        f

      :error ->
        Logger.warning("RuntimeEnvs: invalid float value from SSM: #{inspect(value)}")
        fallback
    end
  end

  defp parse_integer(value, fallback) do
    case Integer.parse(String.trim(value)) do
      {i, _} ->
        i

      :error ->
        Logger.warning("RuntimeEnvs: invalid integer value from SSM: #{inspect(value)}")
        fallback
    end
  end

  defp parse_integer_list(value, _fallback) do
    value
    |> String.split(",", trim: true)
    |> Enum.reduce([], fn str, acc ->
      case Integer.parse(String.trim(str)) do
        {int, ""} -> [int | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp fetch_user_labels(fallback) do
    case fetch_raw_param(@ssm_prefix <> "user_labels") do
      {:ok, value} -> parse_user_labels(value)
      :error -> fallback
    end
  end

  # Mesmo formato do user_labels ("nome:valor;nome:valor"), mapeando nome de
  # contexto -> voice_id da ElevenLabs
  defp fetch_elevenlabs_voices(fallback) do
    case fetch_raw_param(@ssm_prefix <> "elevenlabs_voices") do
      {:ok, value} -> parse_user_labels(value)
      :error -> fallback
    end
  end

  # Aceita o mapa direto ou a mesma string do SSM ("default:id;male_1:id"),
  # para o override de dev poder usar qualquer um dos dois
  @doc false
  def normalize_voices(value) when is_map(value), do: value
  def normalize_voices(value) when is_binary(value), do: parse_user_labels(value)
  def normalize_voices(_), do: %{}

  @doc false
  def parse_user_labels(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, ":", parts: 2) do
        [id, label] ->
          Map.put(acc, String.trim(id), label |> String.trim() |> String.trim("\""))

        _ ->
          acc
      end
    end)
  end
end
