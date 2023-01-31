defmodule GptTalkerbot.Repo do
  use Ecto.Repo,
    otp_app: :gpt_talkerbot,
    adapter: Ecto.Adapters.Postgres
end
