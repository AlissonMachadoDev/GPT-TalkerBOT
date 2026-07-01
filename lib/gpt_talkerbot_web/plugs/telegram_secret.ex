defmodule GptTalkerbotWeb.Plugs.TelegramSecret do
  @moduledoc """
  Valida o header X-Telegram-Bot-Api-Secret-Token enviado pelo Telegram
  em cada update do webhook (registrado via secret_token no setWebhook).

  Se :telegram_webhook_secret não estiver configurado, a validação é
  pulada com um warning — permite rodar sem secret em dev.
  """

  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:gpt_talkerbot, :telegram_webhook_secret, "") do
      "" ->
        Logger.warning("TelegramSecret: telegram_webhook_secret not set, skipping webhook validation")
        conn

      secret ->
        if get_req_header(conn, "x-telegram-bot-api-secret-token") == [secret] do
          conn
        else
          Logger.warning("TelegramSecret: rejected webhook call with missing/invalid secret token")

          conn
          |> send_resp(403, "")
          |> halt()
        end
    end
  end
end
