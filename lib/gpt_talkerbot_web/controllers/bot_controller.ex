defmodule GptTalkerbotWeb.BotController do
  alias GptTalkerbotWeb.BotController
  use GptTalkerbotWeb, :controller

  require Logger

  alias GptTalkerbot.{Telegram, Access, ChatMembers, GifMemory, Interjector, MoodTracker, Reactor, RuntimeEnvs}
  alias GptTalkerbot.GroupMessageCache
  alias GptTalkerbot.Telegram.{ContentDescriber, RatoCommands}
  alias BotController.Administrator

  @ratobo_regex ~r/rato\s*b[oôóò]t?/iu

  @admin_commands ~w(/setproduction /updatevariables /setgrok /setopenai /cleardatabase /resortearhumor)

  @private_commands Administrator.private_commands()
  @group_commands Administrator.group_commands()

  # Os patterns das clauses só discriminam o TIPO do update (texto, legenda,
  # enquete...); chat_id/from/from_id chegam extraídos pelo TelegramAllowed
  # em conn.assigns

  def receive(conn, %{"message" => %{"text" => command}})
      when command in @admin_commands do
    if conn.assigns.owner?, do: run_admin_command(command, conn.assigns.chat_id)
    send_resp(conn, 204, "")
  rescue
    e ->
      log_rescue(command, e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  def receive(conn, %{"message" => %{"text" => text, "from" => %{"is_bot" => false}} = message})
      when is_binary(text) do
    %{chat_id: chat_id, from: from, from_id: user_id} = conn.assigns

    GroupMessageCache.add_message(chat_id, from["first_name"] || "Usuário", text)
    ChatMembers.track_async(chat_id, from)

    cond do
      ratobo?(text) ->
        handle_bot(conn, message)

      String.starts_with?(text, "/") ->
        handle_slash_command(conn, message, text, user_id)

      true ->
        Reactor.maybe_react(chat_id, message["message_id"])
        Interjector.maybe_interject(chat_id)
        GifMemory.maybe_send(chat_id)
        send_resp(conn, 204, "")
    end
  rescue
    e ->
      log_rescue("user message", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  def receive(
        conn,
        %{"message" => %{"text" => text, "from" => %{"username" => "Channel_Bot", "is_bot" => true}} = message}
      )
      when is_binary(text) do
    name = get_in(message, ["sender_chat", "title"]) || "Canal"
    GroupMessageCache.add_message(conn.assigns.chat_id, name, text)

    if ratobo?(text) do
      handle_bot(conn, message)
    else
      send_resp(conn, 204, "")
    end
  rescue
    e ->
      log_rescue("channel message", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  # Mídia com legenda (foto, vídeo, GIF...): a legenda dispara o bot e o
  # conteúdo descrito entra no buffer do grupo
  def receive(conn, %{"message" => %{"caption" => caption, "from" => %{"is_bot" => false}} = message})
      when is_binary(caption) do
    %{chat_id: chat_id, from: from} = conn.assigns

    GroupMessageCache.add_message(
      chat_id,
      from["first_name"] || "Usuário",
      ContentDescriber.describe(message) || caption
    )

    ChatMembers.track_async(chat_id, from)

    if message["animation"] do
      GifMemory.remember(chat_id, message["animation"])
    end

    if ratobo?(caption) do
      handle_bot(conn, message)
    else
      send_resp(conn, 204, "")
    end
  rescue
    e ->
      log_rescue("captioned media", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  # Enquetes de usuários entram no buffer do grupo como texto descrito
  def receive(conn, %{"message" => %{"poll" => _poll, "from" => %{"is_bot" => false}} = message}) do
    %{chat_id: chat_id, from: from} = conn.assigns

    GroupMessageCache.add_message(chat_id, from["first_name"] || "Alguém", ContentDescriber.describe(message))
    ChatMembers.track_async(chat_id, from)

    send_resp(conn, 204, "")
  rescue
    e ->
      log_rescue("poll message", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  # GIFs postados no grupo entram na memória do bot (para o envio aleatório)
  def receive(conn, %{"message" => %{"animation" => animation, "from" => %{"is_bot" => false}}}) do
    %{chat_id: chat_id, from: from} = conn.assigns

    ChatMembers.track_async(chat_id, from)
    GifMemory.remember(chat_id, animation)

    send_resp(conn, 204, "")
  rescue
    e ->
      log_rescue("animation", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  # Service messages de entrada/saída mantêm o registro de membros em dia
  def receive(conn, %{"message" => %{"new_chat_members" => members}}) when is_list(members) do
    Enum.each(members, &ChatMembers.track(conn.assigns.chat_id, &1))
    send_resp(conn, 204, "")
  rescue
    e ->
      log_rescue("new_chat_members", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  def receive(conn, %{"message" => %{"left_chat_member" => user}}) do
    ChatMembers.mark_left(conn.assigns.chat_id, user)
    send_resp(conn, 204, "")
  rescue
    e ->
      log_rescue("left_chat_member", e, __STACKTRACE__)
      send_resp(conn, 204, "")
  end

  def receive(conn, _params), do: send_resp(conn, 204, "")

  defp handle_slash_command(conn, message, "/" <> rest, user_id) do
    command =
      rest
      |> String.split(" ", parts: 2)
      |> List.first()
      # comandos em grupo chegam como /humor@gpt_talkerbot
      |> String.split("@")
      |> List.first()

    chat_type = get_in(message, ["chat", "type"])

    cond do
      command in RatoCommands.commands() ->
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

  defp run_admin_command("/setproduction", _chat_id),
    do: GptTalkerbotWeb.Services.Telegram.set_production_mode()

  defp run_admin_command("/updatevariables", _chat_id), do: RuntimeEnvs.update_variables()

  defp run_admin_command("/setgrok", _chat_id), do: RuntimeEnvs.set_current_service(:grok)

  defp run_admin_command("/setopenai", _chat_id), do: RuntimeEnvs.set_current_service(:openai)

  defp run_admin_command("/resortearhumor", chat_id) do
    mood = MoodTracker.reset()

    GptTalkerbotWeb.Services.Telegram.send_message(%{
      chat_id: to_string(chat_id),
      text: "🎲 Humor global re-sorteado. Agora eu tô no modo #{mood}."
    })
  end

  defp run_admin_command("/cleardatabase", chat_id) do
    GptTalkerbot.Memory.wipe_all()

    GptTalkerbotWeb.Services.Telegram.send_message(%{
      chat_id: to_string(chat_id),
      text: "🐀 Amnésia total instalada. Conversas, fatos e rancores: tudo formatado."
    })
  end

  defp log_rescue(context, exception, stacktrace) do
    Logger.error(
      "BotController: error processing #{context}: " <>
        Exception.format(:error, exception, stacktrace)
    )
  end
end
