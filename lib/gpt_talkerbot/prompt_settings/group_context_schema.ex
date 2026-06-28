defmodule GptTalkerbot.PromptSettings.GroupContextSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "group_contexts" do
    field :chat_id, :string
    field :context, :string, default: ""

    timestamps(inserted_at: false)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:chat_id, :context])
    |> validate_required([:chat_id, :context])
    |> unique_constraint(:chat_id)
  end
end
