defmodule GptTalkerbot.Repo.Migrations.CreateWarnEntries do
  use Ecto.Migration

  def change do
    create table(:warn_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chat_id, :string, null: false
      add :user_id, :string, null: false
      add :first_name, :string
      add :issuer_name, :string
      add :offending_message, :text
      add :request_message, :text
      add :bot_response, :text
      add :forgiven, :boolean, null: false, default: false

      timestamps()
    end

    create index(:warn_entries, [:chat_id, :user_id])
  end
end
