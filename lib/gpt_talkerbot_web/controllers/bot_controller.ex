defmodule GptTalkerbotWeb.BotController do
  alias GptTalkerbotWeb.BotController
  use GptTalkerbotWeb, :controller

  require Logger
  alias GptTalkerbot.Telegram
  alias GptTalkerbot.Access
  alias GptTalkerbot.Commands
  alias BotController.Administrator
  # alias GptTalkerbot.Commands

  @administrator_commands Administrator.administrator_commands()

  def receive(
        conn,
        %{
          "message" =>
            %{
              "text" => "/" <> text,
              "chat" => %{"type" => "private"},
              "from" => %{"id" => user_id, "is_bot" => false}
            } = message
        } = _params
      ) do
    command = text |> String.split(" ", parts: 2) |> List.first()

    if Access.is_registered(user_id) do
      user_commands = Commands.list_user_command_names(user_id)

      cond do
        command in @administrator_commands ->
          apply(Administrator, String.to_atom(command), [
            message
          ])

        command in user_commands ->
          handle_bot(conn, message)

        true ->
          nil
      end
    end

    send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" =>
            %{
              "text" => "/" <> text,
              "chat" => %{"id" => chat_id, "type" => "group"},
              "from" => %{"id" => user_id, "is_bot" => false}
            } = message
        } = _params
      ) do
    command = text |> String.split(" ", parts: 2) |> List.first()

    if Access.is_registered(user_id) and Access.is_group_registered(chat_id) do
      commands = Commands.list_group_commands(chat_id)

      if command in commands do
        Administrator.register2(message)
      end
    end

    send_resp(conn, 204, "")
  end

  def receive(conn, params) do
    IO.inspect(params)
    send_resp(conn, 204, "")
  end

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
