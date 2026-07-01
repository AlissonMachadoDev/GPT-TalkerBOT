defmodule GptTalkerbot.Repo.Migrations.CreateUserWarns do
  use Ecto.Migration

  def change do
    create table(:user_warns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, :string, null: false
      add :user_id, :string, null: false
      add :first_name, :string
      add :count, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:user_warns, [:chat_id, :user_id])
  end
end
