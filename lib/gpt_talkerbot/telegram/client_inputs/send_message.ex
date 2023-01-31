defmodule GptTalkerbot.Telegram.ClientInputs.SendMessage do
  @moduledoc false

  use GptTalkerbot.Telegram.ClientInputs

  alias Ecto.Changeset

  defmodule InlineKeyboardMarkup do
    use Ecto.Schema
    @derive Jason.Encoder

    embedded_schema do
      field :inline_keyboard, {:array, {:array, :map}}, default: [[]]
      # embeds_many :inline_keyboard, InlineKeyboardButton
    end
  end

  embedded_schema do
    field :chat_id, :integer
    field :text, :string
    field :parse_mode, :string
    field :caption_entities, {:array, :map}
    field :disable_web_page_preview, :boolean
    field :disable_notification, :boolean
    field :reply_to_message_id, :string
    field :allow_sending_without_reply, :boolean

    embeds_one :reply_markup, InlineKeyboardMarkup
  end

  @impl true
  def cast(params) do
    %__MODULE__{}
    |> Changeset.cast(params, [
      :chat_id,
      :text,
      :parse_mode,
      :caption_entities,
      :disable_web_page_preview,
      :disable_notification,
      :reply_to_message_id,
      :allow_sending_without_reply
    ])
    |> Changeset.validate_required([:chat_id, :text])
    |> put_chat_id()
    |> Changeset.cast_embed(:reply_markup, with: &reply_markup_changeset/2)
  end

  defp put_chat_id(%Ecto.Changeset{params: params} = changeset) do
    Ecto.Changeset.put_change(
      changeset,
      :chat_id,
      Changeset.get_change(changeset, :chat_id, params["chat_id"] |> String.to_integer())
    )
  end

  defp reply_markup_changeset(schema, params) do
    schema
    |> Changeset.cast(params, [:inline_keyboard])

    # |> Changeset.cast_embed(:inline_keyboard, with: &inline_keyboard_changeset/2)
  end
end
