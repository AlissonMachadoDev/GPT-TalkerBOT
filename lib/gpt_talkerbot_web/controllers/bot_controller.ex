defmodule GptTalkerbotWeb.BotController do
  use GptTalkerbotWeb, :controller

  require Logger
  alias GptTalkerbot.Telegram

  def receive(
        conn,
        %{
          "message" =>
            %{
              "text" => "/" <> _text
            } = message
        }
      ) do
    handle_bot(conn, message)
  end

  def receive(conn, _), do: send_resp(conn, 204, "")

  defp handle_bot(conn, message) do
    with {:ok, message} <- Telegram.build_message(message),
         :ok <- Telegram.enqueue_processing!(message) do
      Logger.info("Message enqueued for later processing")
      send_resp(conn, 204, "")
    else
      _ ->
        send_resp(conn, 204, "")
    end
  end
end
