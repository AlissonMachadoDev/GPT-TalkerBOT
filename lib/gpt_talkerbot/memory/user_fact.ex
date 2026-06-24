defmodule GptTalkerbot.Memory.UserFact do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "user_facts" do
    field :user_id, :string
    field :key, :string
    field :value, :string

    timestamps()
  end

  def changeset(fact, attrs) do
    fact
    |> cast(attrs, [:user_id, :key, :value])
    |> validate_required([:user_id, :key, :value])
    |> unique_constraint(:key, name: :user_facts_user_id_key_index)
  end
end
