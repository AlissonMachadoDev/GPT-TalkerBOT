defmodule GptTalkerbot.Repo.Migrations.CreateGroupMessages do
  use Ecto.Migration

  def change do
    create table(:group_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, :string, null: false
      add :sender_name, :string, null: false
      add :content, :text, null: false

      timestamps(updated_at: false)
    end

    create index(:group_messages, [:chat_id, :inserted_at])
  end
end
