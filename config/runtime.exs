import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/gpt_talkerbot start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :gpt_talkerbot, GptTalkerbotWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :gpt_talkerbot, GptTalkerbot.Repo,
    ssl: false,
    url: database_url,
    pool_size: 20,
    queue_target: 10_000,
    queue_interval: 10_000,
    timeout: 60_000,
    migration_timeout: 120_000,
    socket_options: maybe_ipv6

  # ssl_opts: [
  #   verify: :verify_peer,
  #   cacertfile: "/etc/ssl/certs/rds-ca-global.pem",
  #   server_name_indication: String.to_charlist(URI.parse(database_url).host || ""),
  #   versions: [:"tlsv1.2", :"tlsv1.3"]
  # ]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = "gpt-talkerbot.alissonmachado.dev"
  port = "4004"

  config :gpt_talkerbot, GptTalkerbotWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

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
  config :gpt_talkerbot, :default_prompt, System.get_env("DEFAULT_PROMPT", "")
  config :gpt_talkerbot, :telegram_api_key, System.get_env("TELEGRAM_API_KEY", "")

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :gpt_talkerbot, GptTalkerbot.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
