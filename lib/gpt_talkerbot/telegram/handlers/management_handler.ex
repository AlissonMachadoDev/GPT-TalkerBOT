defmodule GptTalkerbot.Telegram.Handlers.ManagementHandler do
  @moduledoc """
  Just logs the message
  """

  require Logger
  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.Telegram

  @behaviour GptTalkerbot.Telegram.Handlers

  @impl true

  def handle(%Message{text: "/management new_user", from: %{"id" => user_id}} = message),
    do: new_user(user_id, message)

  def handle(%Message{message_id: id}) do
    {:ok, id}
  end

  defp set_api_key() do
    # set api key to a user, turning him a master user
  end

  defp add_group() do
    # verify if the user is a master user
    # create a group with the user as owner
    # add a group to the user
  end

  defp remove_group() do
    # verify if the user is a master user
    # remove a group from the user
  end

  defp create_invite_token() do
    # verify if the user is a master user
    # the param is the telegram username
    # create an invite token for the user
    # return the token
  end

  defp dissociate_user() do
    # verify if the user is a master user
    # dissociate the slave user from the master user
    # notify the user that he doesn't have access to the bot anymore
  end

  defp new_user(user_id, message) do
    # validate invite token on user association require
    # create user with telegram_id
    nil
  end

  defp send_message(message, text) do
    %{
      chat_id: message.chat_id,
      reply_to_message_id: message.message_id,
      text: text
    }
    |> Telegram.send_message()
  end
end
