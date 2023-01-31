defmodule GptTalkerbotWeb.BotController do
  use GptTalkerbotWeb, :controller

  require Logger

  def receive(conn, %{"message" => %{"text" => _any}}), do: send_resp(conn, 204, "")

end
