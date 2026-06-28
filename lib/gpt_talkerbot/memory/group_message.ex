defmodule GptTalkerbot.Memory.GroupMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "group_messages" do
    field :chat_id, :string
    field :sender_name, :string
    field :content, :string

    timestamps(updated_at: false)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [:chat_id, :sender_name, :content])
    |> validate_required([:chat_id, :sender_name, :content])
  end
end
