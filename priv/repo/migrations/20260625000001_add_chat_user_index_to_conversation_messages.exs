defmodule GptTalkerbot.Repo.Migrations.AddChatUserIndexToConversationMessages do
  use Ecto.Migration

  def change do
    create index(:conversation_messages, [:chat_id, :user_id, :inserted_at])
  end
end
