defmodule GptTalkerbot.Access.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :api_key, :string
    field :telegram_id, :string

    belongs_to :master_user, GptTalkerbot.Access.User
    has_many :slave_users, GptTalkerbot.Access.User, foreign_key: :master_user_id
    has_many :groups, GptTalkerbot.Access.Group
    has_many :commands, GptTalkerbot.Commands.Command

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:telegram_id, :api_key, :master_user_id])
    |> validate_required([:telegram_id])
    |> unique_constraint(:telegram_id)
  end
end
