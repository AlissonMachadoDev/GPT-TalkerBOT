defmodule GptTalkerbotWeb.BotController do
  use GptTalkerbotWeb, :controller

  require Logger
  alias GptTalkerbot.Telegram

  @allowed_users Application.get_env(:gpt_talkerbot, :allowed_users)
  @allowed_groups [
    -1001728821884, #Cantinho do Frankie
    -1001872407477 #HD Externo
  ]



  # def receive(conn, %{"message" => %{"forward_from_chat" => %{}, "chat" => %{"id" => chat_id}, "from" => %{"id" => user_id}} = message} = _params) when (user_id in @allowed_users or  @allowed_users == [] or chat_id in @allowed_groups) do
  #   handle_bot(conn, message)
  # end


  def receive(conn, %{"message" => %{"chat" => %{"id" => chat_id}, "text" => "/ratobo@gpt_talkerbot " <> _text, "from" => %{"id" => user_id}} = message} = _params) when (user_id in @allowed_users or @allowed_users == []  or chat_id in @allowed_groups) do
    handle_bot(conn, message)
  end

  def receive(conn, %{"message" => %{"chat" => %{"id" => chat_id}, "text" => "/ratobo " <> _text, "from" => %{"id" => user_id}} = message} = _params) when (user_id in @allowed_users or  @allowed_users == [] or chat_id in @allowed_groups) do
    handle_bot(conn, message)
  end

  def receive(conn, %{"message" => %{"chat" => %{"id" => chat_id}, "text" => "/debose", "from" => %{"id" => user_id}} = message} = _params) when (user_id in @allowed_users or  @allowed_users == [] or chat_id in @allowed_groups) do
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
