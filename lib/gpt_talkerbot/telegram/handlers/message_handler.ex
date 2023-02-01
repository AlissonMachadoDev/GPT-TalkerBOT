defmodule GptTalkerbot.Telegram.Handlers.MessageHandler do
  @moduledoc """
  Sends a simple help message
  """

  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.Telegram
  @behaviour GptTalkerbot.Telegram.Handlers

  def handle(%Message{chat_id: c_id, message_id: m_id, text: text}) do
    %{
      chat_id: c_id,
      text: text
    }
    |> Telegram.send_message()
  end
end
