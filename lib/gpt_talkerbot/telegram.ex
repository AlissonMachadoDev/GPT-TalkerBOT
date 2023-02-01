defmodule GptTalkerbot.Telegram do
  require Logger

  alias GptTalkerbot.Telegram.{Message}
  alias GptTalkerbot.RMQPublisher

  def build_message(params) do
    params
    |> Message.cast()
    |> case do
      %Ecto.Changeset{valid?: true} = changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}

      changeset ->
        {:error, changeset}
    end
  end

  def rebuild_message(params) do
    params
    |> Message.recast()
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
end
