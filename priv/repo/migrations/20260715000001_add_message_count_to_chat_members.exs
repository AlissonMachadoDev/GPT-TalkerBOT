defmodule GptTalkerbot.Repo.Migrations.AddMessageCountToChatMembers do
  use Ecto.Migration

  def change do
    alter table(:chat_members) do
      add :message_count, :integer, null: false, default: 0
    end
  end
end
