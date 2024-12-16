defmodule GptTalkerbot.Commands.Command do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "commands" do
    field :content, :string
    field :enabled, :boolean, default: true
    field :key, :string

    belongs_to :user, GptTalkerbot.Access.User

    timestamps()
  end

  @doc false
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:key, :content, :enabled, :user_id])
    |> validate_required([:key, :content, :enabled, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
