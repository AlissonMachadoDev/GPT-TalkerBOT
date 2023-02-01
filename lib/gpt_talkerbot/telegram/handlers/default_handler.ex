defmodule GptTalkerbot.Telegram.Handlers.DefaultHandler do
  @moduledoc """
  Just logs the message
  """

  require Logger

  alias GptTalkerbot.Telegram.Message

  @behaviour GptTalkerbot.Telegram.Handlers

  @impl true
  def handle(%Message{message_id: id}) do

    {:ok, nil}
  end
end
