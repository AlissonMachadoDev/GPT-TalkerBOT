defmodule GptTalkerbot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Start the Ecto repository
        GptTalkerbot.Repo,
        # Start the Telemetry supervisor
        GptTalkerbotWeb.Telemetry,
        # Start the PubSub system
        {Phoenix.PubSub, name: GptTalkerbot.PubSub},
        # Start the Endpoint (http/https)
        GptTalkerbotWeb.Endpoint
      ] ++
        broker_children() ++
        [
          GptTalkerbot.RuntimeEnvs,
          GptTalkerbot.MoodTracker,
          GptTalkerbot.Interjector,
          GptTalkerbot.DailySummary,
          GptTalkerbot.GroupMessageCache,
          GptTalkerbot.PromptSettings.GroupContext
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GptTalkerbot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Desligado em test (config :gpt_talkerbot, :start_broker, false) para não
  # exigir RabbitMQ de pé
  defp broker_children do
    if Application.get_env(:gpt_talkerbot, :start_broker, true) do
      [GptTalkerbot.RMQPublisher, GptTalkerbot.BotProcessor]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GptTalkerbotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
