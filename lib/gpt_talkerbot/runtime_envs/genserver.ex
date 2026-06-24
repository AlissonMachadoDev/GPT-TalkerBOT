defmodule GptTalkerbot.RuntimeEnvs.GenServer do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %{
      openai_api_key: Application.get_env(:gpt_talkerbot, :openai_api_key, ""),
      grok_api_key: Application.get_env(:gpt_talkerbot, :grok_api_key, ""),
      using: :openai,
      mood: :normal,
      message_count: 0
    }

    {:ok, state}
  end

  def get_current_service, do: GenServer.call(__MODULE__, :get_current_service)
  def get_openai_api_key, do: GenServer.call(__MODULE__, :get_openai_api_key)
  def get_grok_api_key, do: GenServer.call(__MODULE__, :get_grok_api_key)
  def get_mood, do: GenServer.call(__MODULE__, :get_mood)

  def set_current_service(service) when service in [:openai, :grok] do
    GenServer.cast(__MODULE__, {:set_current_service, service})
  end

  def set_mood(mood) when mood in [:normal, :grumpy, :excited, :sarcastic] do
    GenServer.cast(__MODULE__, {:set_mood, mood})
  end

  def increment_messages, do: GenServer.cast(__MODULE__, :increment_messages)

  @impl true
  def handle_call(:get_current_service, _from, state), do: {:reply, state.using, state}
  def handle_call(:get_openai_api_key, _from, state), do: {:reply, state.openai_api_key, state}
  def handle_call(:get_grok_api_key, _from, state), do: {:reply, state.grok_api_key, state}
  def handle_call(:get_mood, _from, state), do: {:reply, state.mood, state}

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
end
