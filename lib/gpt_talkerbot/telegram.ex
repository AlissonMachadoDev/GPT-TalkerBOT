defmodule GptTalkerbot.Telegram do
  require Logger

  alias GptTalkerbot.Telegram.{Message}
  alias GptTalkerbot.RMQPublisher

  def build_message(params) do
    params
    |> format_params()
    |> Message.cast()
    |> case do
      %Ecto.Changeset{valid?: true} = changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}

      changeset ->
        {:error, changeset}
    end
  end

  @doc """
  Processes a message with its handler
  """
  def process_message(%Message{} = m) do
    with {:ok, handler} <- GptTalkerbot.Telegram.Handlers.get_handler(m) do
      handler.handle(m)
    end
  end

  @doc """
  Enqueues processing for a message

  Publishes it as an event in the pubsub
  """
  def enqueue_processing!(%Message{} = m) do
    RMQPublisher.publish_message(m)
  end

  defp format_params(message) do
    message
    |> format_channel_from()
    |> format_channel_reply_to_message()
  end

  defp format_channel_from(%{"from" => %{"username" => "Channel_Bot"}} = message) do
    name = message["sender_chat"]["title"] || "Channel Bot"
    id = message["sender_chat"]["id"] || message["from"]["id"]
    from = message["from"]
    |> Map.put("first_name", name)
    |> Map.put("id", id)
    |> Map.put("username", "formatted_channel_bot")

    Map.put(message, "from", from)
  end

  defp format_channel_from(message), do: message

  defp format_channel_reply_to_message(%{"reply_to_message" => %{"from" => %{"username" => "Channel_Bot"}} = reply} = message) do
    name = reply["sender_chat"]["title"] || "Channel Bot"
    id = reply["sender_chat"]["id"] || reply["from"]["id"]
    from = reply["from"]
    |> Map.put("first_name", name)
    |> Map.put("id", id)
    |> Map.put("username", "formatted_channel_bot")

    Map.put(message, "reply_to_message", Map.put(reply, "from", from))
  end

  defp format_channel_reply_to_message(message), do: message
end
