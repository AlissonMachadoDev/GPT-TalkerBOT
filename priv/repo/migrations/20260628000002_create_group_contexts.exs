defmodule GptTalkerbot.Repo.Migrations.CreateGroupContexts do
  use Ecto.Migration

  def change do
    create table(:group_contexts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, :string, null: false
      add :context, :text, null: false, default: ""

      timestamps(inserted_at: false)
    end

    create unique_index(:group_contexts, [:chat_id])
  end
end
