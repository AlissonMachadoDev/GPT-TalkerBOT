defmodule GptTalkerbotWeb.BotController do
  alias GptTalkerbotWeb.BotController
  use GptTalkerbotWeb, :controller

  require Logger

  alias GptTalkerbot.{Telegram, Access, Interjector, MoodTracker, Reactor, RuntimeEnvs}
  alias GptTalkerbot.GroupMessageCache
  alias GptTalkerbot.Telegram.RatoCommands
  alias BotController.Administrator

  @ratobo_regex ~r/rato\s*b[oôóò]t?/iu

  defp owner_id, do: RuntimeEnvs.get_owner_id()
  defp allowed_users, do: RuntimeEnvs.get_allowed_users()
  defp allowed_groups, do: RuntimeEnvs.get_allowed_groups()

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
    e ->
      log_rescue("setproduction", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" => %{
            "chat" => %{"id" => chat_id},
            "text" => "/updatevariables",
            "from" => %{"id" => user_id}
          }
        }
      ) do
    if is_admin_allowed?(user_id, chat_id), do: RuntimeEnvs.update_variables()
    send_resp(conn, 204, "")
  rescue
    e ->
      log_rescue("updatevariables", e, __STACKTRACE__)
      send_resp(conn, 204, "")
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
    e ->
      log_rescue("setgrok", e, __STACKTRACE__)
      send_resp(conn, 204, "")
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
    e ->
      log_rescue("setopenai", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" => %{
            "chat" => %{"id" => chat_id},
            "text" => "/cleardatabase",
            "from" => %{"id" => user_id}
          }
        }
      ) do
    if is_admin_allowed?(user_id, chat_id) do
      GptTalkerbot.Memory.wipe_all()

      GptTalkerbotWeb.Services.Telegram.send_message(%{
        chat_id: to_string(chat_id),
        text: "🐀 Amnésia total instalada. Conversas, fatos e rancores: tudo formatado."
      })
    end

    send_resp(conn, 204, "")
  rescue
    e ->
      log_rescue("cleardatabase", e, __STACKTRACE__)
      send_resp(conn, 204, "")
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
    name = get_in(message, ["from", "first_name"]) || "Usuário"
    GroupMessageCache.add_message(chat_id, name, text)

    allowed? = is_allowed?(user_id, chat_id)
    if allowed?, do: MoodTracker.note_activity(chat_id)

    cond do
      ratobo?(text) and allowed? ->
        handle_bot(conn, message)

      String.starts_with?(text, "/") ->
        handle_slash_command(conn, message, text, user_id, chat_id)

      allowed? ->
        Reactor.maybe_react(chat_id, message["message_id"])
        Interjector.maybe_interject(chat_id)
        send_resp(conn, 204, "")

      true ->
        send_resp(conn, 204, "")
    end
  rescue
    e ->
      log_rescue("user message", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{
          "message" => %{
            "text" => text,
            "chat" => %{"id" => chat_id},
            "from" => %{"username" => "Channel_Bot", "is_bot" => true}
          } = message
        }
      )
      when is_binary(text) do
    name = get_in(message, ["sender_chat", "title"]) || "Canal"
    GroupMessageCache.add_message(chat_id, name, text)

    if ratobo?(text) and is_allowed?(chat_id, chat_id) do
      handle_bot(conn, message)
    else
      send_resp(conn, 204, "")
    end
  rescue
    e ->
      log_rescue("channel message", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  def receive(conn, _params), do: send_resp(conn, 204, "")

  defp handle_slash_command(conn, message, "/" <> rest, user_id, chat_id) do
    command =
      rest
      |> String.split(" ", parts: 2)
      |> List.first()
      # comandos em grupo chegam como /humor@gpt_talkerbot
      |> String.split("@")
      |> List.first()

    chat_type = get_in(message, ["chat", "type"])

    cond do
      command in RatoCommands.commands() and is_allowed?(user_id, chat_id) ->
        RatoCommands.handle(command, message)

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

  # Fail closed: se allowed_groups vier vazio (ex.: falha no fetch do SSM),
  # o bot fica fechado em vez de aberto para o mundo
  defp is_allowed?(user_id, chat_id) do
    user_id in allowed_users() or chat_id in allowed_groups()
  end

  defp log_rescue(context, exception, stacktrace) do
    Logger.error(
      "BotController: error processing #{context}: " <>
        Exception.format(:error, exception, stacktrace)
    )
  end
end
