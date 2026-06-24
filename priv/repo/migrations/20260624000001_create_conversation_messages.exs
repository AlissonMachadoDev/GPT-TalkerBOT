defmodule GptTalkerbot.Repo.Migrations.CreateConversationMessages do
  use Ecto.Migration

  def change do
    create table(:conversation_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, :string, null: false
      add :user_id, :string, null: false
      add :role, :string, null: false
      add :content, :text, null: false

      timestamps(updated_at: false)
    end

    create index(:conversation_messages, [:chat_id, :inserted_at])
    create index(:conversation_messages, [:user_id, :inserted_at])
  end
end
