defmodule GptTalkerbot.Repo.Migrations.AddLastMessageAtToChatMembers do
  use Ecto.Migration

  def change do
    alter table(:chat_members) do
      add :last_message_at, :utc_datetime
    end

    create index(:chat_members, [:chat_id, :status, :message_count])
  end
end
