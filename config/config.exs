# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :gpt_talkerbot,
  ecto_repos: [GptTalkerbot.Repo],
  generators: [binary_id: true]

# Configures the endpoint
config :gpt_talkerbot, GptTalkerbotWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: GptTalkerbotWeb.ErrorView, accepts: ~w(json), layout: false],
  pubsub_server: GptTalkerbot.PubSub,
  live_view: [signing_salt: "j8hh6LQ0"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :gpt_talkerbot, GptTalkerbot.Mailer, adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, false

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.29",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

parse_env_list = fn env_var ->
  System.get_env(env_var, "")
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.reduce([], fn str, acc ->
    case Integer.parse(str) do
      {int, ""} -> [int | acc]
      _ -> acc
    end
  end)
  |> Enum.reverse()
end

config :gpt_talkerbot, :allowed_users, parse_env_list.("ALLOWED_USERS")
config :gpt_talkerbot, :allowed_groups, parse_env_list.("ALLOWED_GROUPS")
config :gpt_talkerbot, :openai_api_key, System.get_env("OPENAI_API_KEY", "")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
