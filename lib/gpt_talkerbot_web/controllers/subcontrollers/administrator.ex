defmodule GptTalkerbotWeb.BotController.Administrator do
  alias GptTalkerbotWeb.Services.Telegram
  alias GptTalkerbot.Access

  def administrator_commands do
    [
      "register"
    ]
  end

  def register(%{"chat" => %{"id" => chat_id}, "from" => %{"id" => user_id, "is_bot" => false}}) do
    unless Access.is_registered(user_id) do
      Access.create_user(%{telegram_id: user_id})
      response(chat_id, "registered with success, congratulations!")
    else
      response(chat_id, "Wow, it looks like you're alrealdy registered!")
    end
  end

  def register2(%{"chat" => %{"id" => chat_id}, "from" => %{"id" => user_id, "is_bot" => false}}) do
    unless Access.is_registered(user_id) do
      # Access.create_user(%{telegram_id: user_id})
      response(chat_id, "group registered with success, congratulations!")
    else
      response(chat_id, "Wow, it looks like your group is alrealdy registered!")
    end
  end

  def response(id, text) do
    %{
      chat_id: id,
      text: text
    }
    |> Telegram.send_message()
  end
end
