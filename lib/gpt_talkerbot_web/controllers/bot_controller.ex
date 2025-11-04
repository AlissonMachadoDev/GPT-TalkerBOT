defmodule GptTalkerbotWeb.BotController do
  alias GptTalkerbotWeb.BotController
  use GptTalkerbotWeb, :controller

  require Logger
  alias GptTalkerbot.Telegram
  alias GptTalkerbot.Access
  alias GptTalkerbot.Commands
  alias BotController.Administrator
  alias GptTalkerbot.Commands
  alias GptTalkerbot.RuntimeEnvs.GenServer, as: RuntimeEnvs

  defp owner_id, do: Application.get_env(:gpt_talkerbot, :owner_id, "")

  @private_commands Administrator.private_commands()
  @group_commands Administrator.group_commands()

  defp allowed_users, do: Application.get_env(:gpt_talkerbot, :allowed_users, [])
  defp allowed_groups, do: Application.get_env(:gpt_talkerbot, :allowed_groups, [])

  def receive(
        conn,
        %{
          "message" =>
            %{
              "chat" => %{"id" => chat_id},
              "text" => "/setproduction",
              "from" => %{"id" => user_id}
            } = _message
        } = _params
      ) do
    if is_admin_allowed?(user_id, chat_id) do
      GptTalkerbotWeb.Services.Telegram.set_production_mode()
      send_resp(conn, 204, "")
    else
      send_resp(conn, 204, "")
    end
  rescue
    _ ->
      send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" =>
            %{
              "chat" => %{"id" => chat_id},
              "text" => "/setgrok",
              "from" => %{"id" => user_id}
            } = _message
        } = _params
      ) do
    if is_admin_allowed?(user_id, chat_id) do
      RuntimeEnvs.set_current_service(:grok)
      send_resp(conn, 204, "")
    else
      send_resp(conn, 204, "")
    end
  rescue
    _ ->
      send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" =>
            %{
              "chat" => %{"id" => chat_id},
              "text" => "/setopenai",
              "from" => %{"id" => user_id}
            } = _message
        } = _params
      ) do
    if is_admin_allowed?(user_id, chat_id) do
      RuntimeEnvs.set_current_service(:openai)
      send_resp(conn, 204, "")
    else
      send_resp(conn, 204, "")
    end
  rescue
    _ ->
      send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" =>
            %{
              "chat" => %{"id" => chat_id},
              "text" => "/ratobo@gpt_talkerbot " <> _text,
              "from" => %{"id" => user_id}
            } = message
        } = _params
      ) do
    if is_allowed?(user_id, chat_id) do
      handle_bot(conn, message)
    else
      send_resp(conn, 204, "")
    end
  rescue
    _ ->
      send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" =>
            %{
              "chat" => %{"id" => chat_id},
              "text" => "/ratobo " <> _text,
              "from" => %{"id" => user_id}
            } = message
        } = _params
      ) do
    if is_allowed?(user_id, chat_id) do
      handle_bot(conn, message)
    else
      send_resp(conn, 204, "")
    end
  rescue
    _ ->
      send_resp(conn, 204, "")
  end

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
        command in @private_commands ->
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
  rescue
    _ ->
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

    cond do
      Access.is_group_registered(chat_id) and command in @group_commands ->
        apply(Administrator, String.to_atom(command), [
          message
        ])

      Access.is_group_registered(chat_id) ->
        commands = Commands.list_group_commands(chat_id)

        if command in commands do
          handle_bot(conn, message)
        end

      Access.is_registered(user_id) and command == "register_group" ->
        Administrator.register_group(message)
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

  defp is_admin_allowed?(owner_id, _) do
    owner_id == owner_id()
  end

  defp is_allowed?(user_id, chat_id) do
    user_id in allowed_users() or allowed_groups() == [] or chat_id in allowed_groups()
  end
end
