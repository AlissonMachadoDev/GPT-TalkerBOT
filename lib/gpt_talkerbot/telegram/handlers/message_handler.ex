defmodule GptTalkerbot.Telegram.Handlers.MessageHandler do
  @moduledoc """
  Sends a simple help message
  """

  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.Telegram
  alias GptTalkerbotWeb.Services.OpenAI
  @behaviour GptTalkerbot.Telegram.Handlers

  def handle(%Message{chat_id: c_id, message_id: _m_id, text: text}) do
    {:ok, body} = OpenAI.gpt_completion(text)

    text = List.first(body["choices"])["message"]["content"]

    splited_text =
      String.split_at(text, 3500)
      |> Tuple.to_list()

    Enum.map(splited_text, fn t ->
      %{
        chat_id: c_id,
        text: t
      }
      |> Telegram.send_message()
    end)
  end
end
