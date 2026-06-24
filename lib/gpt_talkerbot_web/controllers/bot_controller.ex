defmodule GptTalkerbotWeb.BotController do
  alias GptTalkerbotWeb.BotController
  use GptTalkerbotWeb, :controller

  require Logger
  alias GptTalkerbot.{Telegram, Access}
  alias BotController.Administrator
  alias GptTalkerbot.RuntimeEnvs.GenServer, as: RuntimeEnvs

  @ratobo_regex ~r/rato\s*b[oôóò]t?/iu

  defp owner_id, do: Application.get_env(:gpt_talkerbot, :owner_id, "")
  defp allowed_users, do: Application.get_env(:gpt_talkerbot, :allowed_users, [])
  defp allowed_groups, do: Application.get_env(:gpt_talkerbot, :allowed_groups, [])

  @private_commands Administrator.private_commands()
  @group_commands Administrator.group_commands()

  def receive(
        conn,
        %{
          "message" => %{
            "chat" => %{"id" => chat_id},
            "text" => "/setproduction",
            "from" => %{"id" => user_id}
          }
        }
      ) do
    if is_admin_allowed?(user_id, chat_id),
      do: GptTalkerbotWeb.Services.Telegram.set_production_mode()

    send_resp(conn, 204, "")
  rescue
    _ -> send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" => %{
            "chat" => %{"id" => chat_id},
            "text" => "/setgrok",
            "from" => %{"id" => user_id}
          }
        }
      ) do
    if is_admin_allowed?(user_id, chat_id), do: RuntimeEnvs.set_current_service(:grok)
    send_resp(conn, 204, "")
  rescue
    _ -> send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" => %{
            "chat" => %{"id" => chat_id},
            "text" => "/setopenai",
            "from" => %{"id" => user_id}
          }
        }
      ) do
    if is_admin_allowed?(user_id, chat_id), do: RuntimeEnvs.set_current_service(:openai)
    send_resp(conn, 204, "")
  rescue
    _ -> send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" => %{
            "text" => text,
            "chat" => %{"id" => chat_id},
            "from" => %{"id" => user_id, "is_bot" => false}
          } = message
        }
      )
      when is_binary(text) do
    cond do
      ratobo?(text) and is_allowed?(user_id, chat_id) ->
        handle_bot(conn, message)

      String.starts_with?(text, "/") ->
        handle_slash_command(conn, message, text, user_id, chat_id)

      true ->
        send_resp(conn, 204, "")
    end
  rescue
    _ -> send_resp(conn, 204, "")
  end

  def receive(conn, _params), do: send_resp(conn, 204, "")

  defp handle_slash_command(conn, message, "/" <> rest, user_id, _chat_id) do
    command = rest |> String.split(" ", parts: 2) |> List.first()
    chat_type = get_in(message, ["chat", "type"])

    cond do
      chat_type == "private" and Access.is_registered(user_id) and
          command in @private_commands ->
        apply(Administrator, String.to_existing_atom(command), [message])

      chat_type in ["group", "supergroup"] and command in @group_commands ->
        apply(Administrator, String.to_existing_atom(command), [message])

      chat_type in ["group", "supergroup"] and Access.is_registered(user_id) and
          command == "register_group" ->
        Administrator.register_group(message)

      true ->
        nil
    end

    send_resp(conn, 204, "")
  end

  defp handle_bot(conn, message) do
    with {:ok, message} <- Telegram.build_message(message),
         :ok <- Telegram.enqueue_processing!(message) do
      Logger.info("Message enqueued for later processing")
      send_resp(conn, 204, "")
    else
      _ -> send_resp(conn, 204, "")
    end
  end

  defp ratobo?(text), do: Regex.match?(@ratobo_regex, text)

  defp is_admin_allowed?(owner_id, _) when is_integer(owner_id),
    do: is_admin_allowed?(Integer.to_string(owner_id), nil)

  defp is_admin_allowed?(user_id, _), do: user_id == owner_id()

  defp is_allowed?(user_id, chat_id) do
    user_id in allowed_users() or allowed_groups() == [] or chat_id in allowed_groups()
  end
end
