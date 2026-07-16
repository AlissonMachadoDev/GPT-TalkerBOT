defmodule GptTalkerbot.ChatMembers.ChatMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "chat_members" do
    field :chat_id, :string
    field :user_id, :string
    field :first_name, :string
    field :username, :string
    field :status, :string, default: "active"
    # Contador de mensagens, incrementado fora do changeset (Repo.update_all)
    field :message_count, :integer, default: 0

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:chat_id, :user_id, :first_name, :username, :status])
    |> validate_required([:chat_id, :user_id])
    |> validate_inclusion(:status, ["active", "left"])
    |> unique_constraint([:chat_id, :user_id])
  end
end
