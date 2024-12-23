defmodule GptTalkerbot.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :telegram_id, :string
      add :api_key, :string
      add :master_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:users, [:master_user_id])
  end
end
