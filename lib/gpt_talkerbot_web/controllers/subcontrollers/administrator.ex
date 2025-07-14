defmodule GptTalkerbotWeb.BotController.Administrator do
  alias GptTalkerbotWeb.Services.Telegram
  alias GptTalkerbot.Access

  def private_commands do
    [
      "register"
    ]
  end

  def group_commands do
    [
      "register_group"
    ]
  end

  def register(%{
        "chat" => %{"id" => chat_id},
        "from" => %{"id" => telegram_user_id, "is_bot" => false}
      }) do
    unless Access.is_registered(telegram_user_id) do
      Access.create_user(%{telegram_id: telegram_user_id})
      send_response(chat_id, "registered with success, congratulations!")
    else
      send_response(chat_id, "Wow, it looks like you're alrealdy registered!")
    end
  end

  def register_group(%{
        "chat" => %{"id" => chat_id},
        "from" => %{"id" => telegram_user_id, "is_bot" => false}
      }) do
    user = Access.get_user_by_telegram_id!(telegram_user_id)

    unless Access.is_user_master?(user) do
      Access.create_group(user, %{telegram_id: chat_id})
      |> handle_group_creation(chat_id)
    else
      send_response(chat_id, "Wow, it looks like you're not alowed to do this!")
    end
  end

  defp handle_group_creation({:ok, _group}, chat_id),
    do: send_response(chat_id, "group registered with success, congratulations!")

  defp handle_group_creation({:error, _}, chat_id),
    do: send_response(chat_id, "Wow, it looks like your group is alrealdy registered!")

  def send_response(id, text) do
    %{
      chat_id: id,
      text: text
    }
    |> Telegram.send_message()
  end
end
