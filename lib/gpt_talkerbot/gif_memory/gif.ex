defmodule GptTalkerbot.GifMemory.Gif do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "gifs" do
    field :chat_id, :string
    field :file_id, :string
    field :file_unique_id, :string
    field :banned, :boolean, default: false

    timestamps()
  end

  def changeset(gif, attrs) do
    gif
    |> cast(attrs, [:chat_id, :file_id, :file_unique_id, :banned])
    |> validate_required([:chat_id, :file_id, :file_unique_id])
    |> unique_constraint([:chat_id, :file_unique_id])
  end
end
