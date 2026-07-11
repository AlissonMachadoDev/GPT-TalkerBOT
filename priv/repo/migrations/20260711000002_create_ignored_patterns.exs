defmodule GptTalkerbot.Repo.Migrations.CreateIgnoredPatterns do
  use Ecto.Migration

  def change do
    create table(:ignored_patterns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, :string, null: false
      add :pattern, :string, null: false

      timestamps()
    end

    create unique_index(:ignored_patterns, [:chat_id, :pattern])
  end
end
