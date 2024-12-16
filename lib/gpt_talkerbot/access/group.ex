defmodule GptTalkerbot.Access.Group do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "groups" do
    field :telegram_id, :string
    field :user_id, :string

    timestamps()
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:telegram_id, :user_id])
    |> validate_required([:telegram_id, :user_id])
  end
end
