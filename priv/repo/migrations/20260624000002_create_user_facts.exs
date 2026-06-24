defmodule GptTalkerbot.Repo.Migrations.CreateUserFacts do
  use Ecto.Migration

  def change do
    create table(:user_facts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :string, null: false
      add :key, :string, null: false
      add :value, :text, null: false

      timestamps()
    end

    create unique_index(:user_facts, [:user_id, :key])
  end
end
