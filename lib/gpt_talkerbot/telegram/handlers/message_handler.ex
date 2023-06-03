defmodule GptTalkerbot.Telegram.Handlers.MessageHandler do
  @moduledoc """
  Sends a simple help message
  """

  alias GptTalkerbotWeb.Services.CustomMessages
  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.Telegram
  alias GptTalkerbotWeb.Services.OpenAI
  @behaviour GptTalkerbot.Telegram.Handlers

  def handle(%Message{text: "/ratobo@gpt_talkerbot debose" <> text} = message),
    do: handle_message(message, "#{text}: #{CustomMessages.debose()}")

  def handle(%Message{text: "/ratobo debose" <> text} = message),
    do: handle_message(message, "#{text}: #{CustomMessages.debose()}")

  def handle(%Message{text: "/ratobo gpt" <> text} = message),
    do: handle_gpt_message(message, text)

  def handle(%Message{text: "/ratobo@gpt_talkerbot gpt" <> text} = message),
    do: handle_gpt_message(message, text)

  def handle(%Message{text: "/ratobo " <> text} = message), do: handle_message(message, text)

  def handle(%Message{text: "/ratobo@gpt_talkerbot " <> text} = message),
    do: handle_message(message, text)

  def handle_message(message, text) do
    text =
      if Map.has_key?(message, :reply_to_message) do
        if is_map(message.reply_to_message) and Map.has_key?(message.reply_to_message, :text),

          do:
            (if(is_bitstring(message.reply_to_message.text)) do
              [text <> ":\n" <> message.reply_to_message.text]
            else
              if(is_bitstring(message.reply_to_message.caption)) do
                [text <> ":\n" <> message.reply_to_message.caption]
              else
                text
              end
            end),
          else: text
      else
        text
      end

    with {:ok, body} <- OpenAI.ada_completion(text) do
      text = List.first(body["choices"])["text"]

      if text == "" do
        send_error(message)
      else
        splited_text =
          String.split_at(text, 3500)
          |> Tuple.to_list()

        Enum.map(splited_text, fn t ->
          %{
            chat_id: message.chat_id,
            reply_to_message_id: message.message_id,
            text: t
          }
          |> Telegram.send_message()
        end)
      end
    else
      {:error, _} ->
        send_error(message)
    end
  end

  def handle_gpt_message(message, text) do
    messages =
      if Map.has_key?(message, :reply_to_message) do
        if is_map(message.reply_to_message) and Map.has_key?(message.reply_to_message, :text),
          do: [
            %{role: :user, content: message.reply_to_message.text},
            %{role: :user, content: text}
          ],
          else: [%{role: :user, content: text}]
      else
        [%{role: :user, content: text}]
      end

    with {:ok, body} <- OpenAI.gpt_completion(messages) do
      text = List.first(body["choices"])["message"]["content"]

      if text == "" do
        send_error(message)
      else
        splited_text =
          String.split_at(text, 3500)
          |> Tuple.to_list()

        Enum.map(splited_text, fn t ->
          %{
            chat_id: message.chat_id,
            reply_to_message_id: message.message_id,
            text: t
          }
          |> Telegram.send_message()
        end)
      end
    else
      {:error, _} ->
        send_error(message)
    end
  end

  def send_error(message) do
    %{
      chat_id: message.chat_id,
      reply_to_message_id: message.message_id,
      text: "your request had an error."
    }
    |> Telegram.send_message()
  end
end
