defmodule GptTalkerbot.Events.TelegramMessage do
  @moduledoc """
  Models a telegram message
  """

  alias GptTalkerbot.Telegram.Message

  @behaviour GptTalkerbot.Events.Event

  @impl true
  def cast(%Message{} = message), do: {:ok, message}
  def cast(params) do
    params
    |> Message.cast()
    |> case do
      %{valid?: true} = changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}

      changeset ->
        {:error, changeset}
    end
  end

  @impl true
  def recast(%Message{} = message), do: {:ok, message}
  def recast(params) do
    params
    |> Message.recast()
    |> case do
      %{valid?: true} = changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}

      changeset ->
        {:error, changeset}
    end
  end
end
