defmodule GptTalkerbot.Repo.Migrations.CreateGifs do
  use Ecto.Migration

  def change do
    create table(:gifs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, :string, null: false
      add :file_id, :text, null: false
      add :file_unique_id, :string, null: false
      add :banned, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:gifs, [:chat_id, :file_unique_id])
  end
end
