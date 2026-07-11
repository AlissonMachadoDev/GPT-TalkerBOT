defmodule GptTalkerbot.IgnoredPatterns.IgnoredPattern do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "ignored_patterns" do
    field :chat_id, :string
    field :pattern, :string

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:chat_id, :pattern])
    |> validate_required([:chat_id, :pattern])
    |> unique_constraint([:chat_id, :pattern])
  end
end
