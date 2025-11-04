defmodule GptTalkerbot.RuntimeEnvs.GenServer do
  @moduledoc """
  GenServer runtime environment configuration
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    openai_api_key = Application.get_env(:gpt_talkerbot, :openai_api_key, "")

    grok_api_key = Application.get_env(:gpt_talkerbot, :grok_api_key, "")

    state = %{
      openai_api_key: openai_api_key,
      grok_api_key: grok_api_key,
      using: :openai
    }

    {:ok, state}
  end

  def get_current_service do
    GenServer.call(__MODULE__, :get_current_service)
  end

  def set_current_service(service) when service in [:openai, :grok] do
    GenServer.cast(__MODULE__, {:set_current_service, service})
  end

  def get_openai_api_key do
    GenServer.call(__MODULE__, :get_openai_api_key)
  end

  def get_grok_api_key do
    GenServer.call(__MODULE__, :get_grok_api_key)
  end

  @impl true
  def handle_call(:get_current_service, _from, state) do
    {:reply, state.using, state}
  end

  def handle_call(:get_openai_api_key, _from, state) do
    {:reply, state.openai_api_key, state}
  end

  def handle_call(:get_grok_api_key, _from, state) do
    {:reply, state.grok_api_key, state}
  end

  @impl true
  def handle_cast({:set_current_service, service}, state) do
    {:noreply, %{state | using: service}}
  end
end
