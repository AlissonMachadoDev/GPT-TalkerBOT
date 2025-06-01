defmodule GptTalkerbot.Telegram.Message do
  @moduledoc """
  Representation of a message with flexible casting for both initial and rebuilt messages
  """
  use Ecto.Schema

  alias Ecto.Changeset

  # maybe move this soon?
  defmodule From do
    use Ecto.Schema

    @derive Jason.Encoder
    embedded_schema do
      field :username, :string
      field :first_name, :string
      field :language_code, :string
      field :telegram_id, :string
    end
  end

  defmodule ReplyToMessage do
    use Ecto.Schema

    @derive Jason.Encoder
    embedded_schema do
      field :chat_id, :string
      field :chat_type, :string
      field :chat_first_name, :string
      field :message_id, :string
      field :text, :string
      embeds_one :from, From
    end
  end

  @derive Jason.Encoder
  embedded_schema do
    field :message_id, :string
    field :chat_id, :string
    field :chat_type, :string
    field :text, :string

    embeds_one :from, From
    embeds_one :reply_to_message, ReplyToMessage
  end

  def cast(params) do
    %__MODULE__{}
    |> Changeset.cast(params, [:text, :chat_id, :chat_type])
    |> Changeset.validate_required([:text])
    |> put_fields(params)
    |> Changeset.cast_embed(:from, with: &from_changeset/2)
    |> Changeset.cast_embed(:reply_to_message, with: &reply_to_message_changeset/2)
  end

  defp reply_to_message_changeset(schema, params) do
    schema
    |> Changeset.cast(params, [:text, :chat_id, :chat_type, :chat_first_name])
    |> put_fields(params)
    |> Changeset.cast_embed(:from, with: &from_changeset/2)
  end

  defp from_changeset(schema, params) do
    schema
    |> Changeset.cast(params, [:first_name, :language_code, :telegram_id, :username])
    |> put_telegram_id(params)
  end

  # Flexible field handling
  defp put_fields(changeset, params) do
    changeset
    |> put_chat_id(params)
    |> put_chat_type(params)
    |> put_message_id(params)
  end

  defp put_chat_id(changeset, %{"chat" => %{"id" => id}}) do
    Changeset.put_change(changeset, :chat_id, Integer.to_string(id))
  end

  defp put_chat_id(changeset, %{"chat_id" => id}) when is_binary(id) do
    Changeset.put_change(changeset, :chat_id, id)
  end

  defp put_chat_id(changeset, _), do: changeset

  defp put_message_id(changeset, %{"message_id" => id}) when is_integer(id) do
    Changeset.put_change(changeset, :message_id, Integer.to_string(id))
  end

  defp put_message_id(changeset, %{"message_id" => id}) when is_binary(id) do
    Changeset.put_change(changeset, :message_id, id)
  end

  defp put_message_id(changeset, _), do: changeset

  defp put_chat_type(changeset, %{"chat" => %{"type" => type}}) do
    Changeset.put_change(changeset, :chat_type, type)
  end

  defp put_chat_type(changeset, %{"chat_type" => type}) when is_binary(type) do
    Changeset.put_change(changeset, :chat_type, type)
  end

  defp put_chat_type(changeset, _), do: changeset

  defp put_telegram_id(changeset, %{"id" => id}) when is_integer(id) do
    Changeset.put_change(changeset, :telegram_id, Integer.to_string(id))
  end

  defp put_telegram_id(changeset, %{"telegram_id" => id}) when is_binary(id) do
    Changeset.put_change(changeset, :telegram_id, id)
  end

  defp put_telegram_id(changeset, _), do: changeset
end
