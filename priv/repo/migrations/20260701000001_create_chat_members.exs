defmodule GptTalkerbot.Repo.Migrations.CreateChatMembers do
  use Ecto.Migration

  def change do
    create table(:chat_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, :string, null: false
      add :user_id, :string, null: false
      add :first_name, :string
      add :username, :string
      add :status, :string, null: false, default: "active"

      timestamps()
    end

    create unique_index(:chat_members, [:chat_id, :user_id])
    create index(:chat_members, [:chat_id, :status])
  end
end
