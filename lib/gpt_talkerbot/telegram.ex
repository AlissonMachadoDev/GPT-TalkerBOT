defmodule GptTalkerbot.Telegram do
  require Logger

  alias GptTalkerbot.Telegram.{Message}
  alias GptTalkerbot.Events

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

  @doc """
    Enqueues processing for a message

    Publishes it as an event in the pubsub
  """
  def enqueue_processing!(%Message{} = m) do
    IO.inspect(m)
    # Logic to publish at RabbitMQ

  end
end
