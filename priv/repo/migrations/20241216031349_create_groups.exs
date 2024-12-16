defmodule GptTalkerbot.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :telegram_id, :string
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:groups, [:user_id])
  end
end
