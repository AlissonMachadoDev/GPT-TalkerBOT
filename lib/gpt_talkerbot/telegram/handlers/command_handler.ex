defmodule GptTalkerbot.Telegram.Handlers.CommandHandler do
  @moduledoc """
  Just logs the message
  """

  require Logger
  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.Telegram
  alias GptTalkerbotWeb.Services.OpenAI
  alias GptTalkerbot.Commands
  alias Commands.Command

  @behaviour GptTalkerbot.Telegram.Handlers

  def handle(%Message{text: "/" <> command_text} = message) do
    {command_key, message_text} =
      String.split(command_text, " ", parts: 2)
      |> then(fn [first, last] -> {String.trim_leading(first, "/"), last} end)

    case Commands.find_command_by_key(command_key) do
      %Command{} = command ->
        process_dynamic_command(message, command, message_text)

      nil ->
        send_message(message, "command not found: #{command_key}")
    end
  end

  @impl true
  def handle(%Message{message_id: id}) do
    {:ok, id}
  end

  defp process_dynamic_command(message, command, message_text) do
    prompt = apply_template(command.content, message_text)

    # OpenAI.completion(prompt)
    with {:ok, response} <-
           {:ok,
            "the command was: #{command}, the params was: #{inspect(message_text)} and the prompt was: #{prompt}"} do
      send_message(message, response)
    end
  end

  def send_message(message, text) do
    %{
      chat_id: message.chat_id,
      reply_to_message_id: message.message_id,
      text: text
    }
    |> Telegram.send_message()
  end

  def apply_template(template, message_text) do
    # Here you can implement your template processing logic
    # For simplicity, we will just return the template with params appended
    "#{template}: #{message_text}"
  end
end
