defmodule GptTalkerbot.Memory.ConversationMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "conversation_messages" do
    field :chat_id, :string
    field :user_id, :string
    field :role, :string
    field :content, :string

    timestamps(updated_at: false)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [:chat_id, :user_id, :role, :content])
    |> validate_required([:chat_id, :user_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
