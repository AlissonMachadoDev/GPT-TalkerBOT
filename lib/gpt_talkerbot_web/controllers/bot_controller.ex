defmodule GptTalkerbotWeb.BotController do
  use GptTalkerbotWeb, :controller

  require Logger
  alias GptTalkerbot.Telegram


  def receive(conn, %{"message" => %{"text" => "querido botzinho, " <> _any} = message} = _params) do
    with {:ok, message} <- Telegram.build_message(message),
         :ok <- Telegram.enqueue_processing!(message) do
      Logger.info("Message enqueued for later processing")
      send_resp(conn, 204, "")
    else
      _ ->
        send_resp(conn, 204, "")
    end
  end

  def receive(conn, %{"message" => %{"text" => any}}) do
    IO.inspect(any, label: "not handling")
    send_resp(conn, 204, "")
  end

end
