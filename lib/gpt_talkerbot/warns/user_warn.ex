defmodule GptTalkerbot.Warns.UserWarn do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "user_warns" do
    field :chat_id, :string
    field :user_id, :string
    field :first_name, :string
    field :count, :integer, default: 0

    timestamps()
  end

  def changeset(warn, attrs) do
    warn
    |> cast(attrs, [:chat_id, :user_id, :first_name, :count])
    |> validate_required([:chat_id, :user_id])
    |> unique_constraint([:chat_id, :user_id])
  end
end
