defmodule GptTalkerbot.Access.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :api_key, :string
    field :master_user_id, :string
    field :telegram_id, :string

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:telegram_id, :api_key, :master_user_id])
    |> validate_required([:telegram_id, :api_key, :master_user_id])
  end
end
