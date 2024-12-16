defmodule GptTalkerbot.Repo.Migrations.CreateCommands do
  use Ecto.Migration

  def change do
    create table(:commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string
      add :content, :string
      add :enabled, :boolean, default: false, null: false
      add :user_id, :string

      timestamps()
    end
  end
end
