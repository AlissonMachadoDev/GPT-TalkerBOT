defmodule GptTalkerbot.Telegram.Handlers.CommandHandler do
  @moduledoc """
  Just logs the message
  """

  require Logger
  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.Telegram
  alias GptTalkerbotWeb.Services.OpenAI

  alias GptTalkerbotWeb.Services.CustomMessages

  @behaviour GptTalkerbot.Telegram.Handlers

  def handle(%Message{text: "/ratobo@gpt_talkerbot debose"} = message), do: send_message(message, "debose")

  def handle(%Message{text: "/debose"} = message), do: send_message(message, "debose")

  def send_message(message, "debose") do
    %{
      chat_id: message.chat_id,
      reply_to_message_id: message.message_id,
      text: CustomMessages.debose()
    }
    |> Telegram.send_message()
  end

  @impl true
  def handle(%Message{message_id: id}) do
    {:ok, id}
  end
end
