defmodule GptTalkerbot.RuntimeEnvs.GenServer do
  use GenServer

  require Logger

  @default_spice_threshold 0.35
  @default_temperature 1.3
  @refresh_interval_ms 12 * 60 * 60 * 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %{
      openai_api_key: Application.get_env(:gpt_talkerbot, :openai_api_key, ""),
      grok_api_key: Application.get_env(:gpt_talkerbot, :grok_api_key, ""),
      using: :grok,
      mood: :normal,
      message_count: 0,
      spice_threshold: fetch_float_param("/gpt_talkerbot/prod/spice_threshold", @default_spice_threshold),
      temperature: fetch_float_param("/gpt_talkerbot/prod/temperature", @default_temperature),
      user_labels: fetch_user_labels(%{})
    }

    schedule_refresh()
    {:ok, state}
  end

  def get_current_service, do: GenServer.call(__MODULE__, :get_current_service)
  def get_openai_api_key, do: GenServer.call(__MODULE__, :get_openai_api_key)
  def get_grok_api_key, do: GenServer.call(__MODULE__, :get_grok_api_key)
  def get_mood, do: GenServer.call(__MODULE__, :get_mood)
  def get_spice_threshold, do: GenServer.call(__MODULE__, :get_spice_threshold)
  def get_temperature, do: GenServer.call(__MODULE__, :get_temperature)
  def get_user_labels, do: GenServer.call(__MODULE__, :get_user_labels)

  def set_current_service(service) when service in [:openai, :grok] do
    GenServer.cast(__MODULE__, {:set_current_service, service})
  end

  def set_mood(mood) when mood in [:normal, :grumpy, :excited, :sarcastic] do
    GenServer.cast(__MODULE__, {:set_mood, mood})
  end

  def increment_messages, do: GenServer.cast(__MODULE__, :increment_messages)

  def update_variables, do: GenServer.cast(__MODULE__, :update_variables)

  @impl true
  def handle_call(:get_current_service, _from, state), do: {:reply, state.using, state}
  def handle_call(:get_openai_api_key, _from, state), do: {:reply, state.openai_api_key, state}
  def handle_call(:get_grok_api_key, _from, state), do: {:reply, state.grok_api_key, state}
  def handle_call(:get_mood, _from, state), do: {:reply, state.mood, state}
  def handle_call(:get_spice_threshold, _from, state), do: {:reply, state.spice_threshold, state}
  def handle_call(:get_temperature, _from, state), do: {:reply, state.temperature, state}
  def handle_call(:get_user_labels, _from, state), do: {:reply, state.user_labels, state}

  @impl true
  def handle_cast({:set_current_service, service}, state) do
    {:noreply, %{state | using: service}}
  end

  def handle_cast({:set_mood, mood}, state) do
    {:noreply, %{state | mood: mood}}
  end

  def handle_cast(:increment_messages, state) do
    count = state.message_count + 1

    mood =
      cond do
        rem(count, 50) == 0 -> :grumpy
        rem(count, 35) == 0 -> :excited
        rem(count, 20) == 0 -> :sarcastic
        true -> state.mood
      end

    {:noreply, %{state | message_count: count, mood: mood}}
  end

  def handle_cast(:update_variables, state) do
    new_state = fetch_variables(state)
    Logger.info("RuntimeEnvs: variables updated (spice_threshold=#{new_state.spice_threshold}, temperature=#{new_state.temperature})")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refresh_variables, state) do
    new_state = fetch_variables(state)
    Logger.info("RuntimeEnvs: scheduled refresh (spice_threshold=#{new_state.spice_threshold}, temperature=#{new_state.temperature})")
    schedule_refresh()
    {:noreply, new_state}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_variables, @refresh_interval_ms)
  end

  defp fetch_variables(state) do
    %{state |
      spice_threshold: fetch_float_param("/gpt_talkerbot/prod/spice_threshold", state.spice_threshold),
      temperature: fetch_float_param("/gpt_talkerbot/prod/temperature", state.temperature),
      user_labels: fetch_user_labels(state.user_labels)
    }
  end

  defp fetch_user_labels(fallback) do
    try do
      "/gpt_talkerbot/prod/user_labels"
      |> ExAws.SSM.get_parameter(with_decryption: true)
      |> ExAws.request()
      |> case do
        {:ok, %{"Parameter" => %{"Value" => value}}} ->
          parse_user_labels(value)
          |> IO.inspect(label: "RuntimeEnvs: fetched user_labels from SSM")

        {:error, reason} ->
          Logger.warning("RuntimeEnvs: failed to fetch user_labels from SSM: #{inspect(reason)}")
          fallback
      end
    rescue
      e ->
        Logger.warning("RuntimeEnvs: exception fetching user_labels from SSM: #{Exception.message(e)}")
        fallback
    catch
      :exit, reason ->
        Logger.warning("RuntimeEnvs: exit fetching user_labels from SSM: #{inspect(reason)}")
        fallback
    end
  end

  defp parse_user_labels(value) do
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

  defp fetch_float_param(param_name, fallback) do
    try do
      param_name
      |> ExAws.SSM.get_parameter(with_decryption: true)
      |> ExAws.request()
      |> case do
        {:ok, %{"Parameter" => %{"Value" => value}}} ->
          case Float.parse(value) do
            {f, _} -> f
            :error ->
              Logger.warning("RuntimeEnvs: invalid float value from SSM #{param_name}: #{inspect(value)}")
              fallback
          end

        {:error, reason} ->
          Logger.warning("RuntimeEnvs: failed to fetch #{param_name} from SSM: #{inspect(reason)}")
          fallback
      end
    rescue
      e ->
        Logger.warning("RuntimeEnvs: exception fetching #{param_name} from SSM: #{Exception.message(e)}")
        fallback
    catch
      :exit, reason ->
        Logger.warning("RuntimeEnvs: exit fetching #{param_name} from SSM: #{inspect(reason)}")
        fallback
    end
  end
end
