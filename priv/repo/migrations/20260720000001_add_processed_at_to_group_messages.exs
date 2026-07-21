defmodule GptTalkerbot.Repo.Migrations.AddProcessedAtToGroupMessages do
  use Ecto.Migration

  def change do
    alter table(:group_messages) do
      add :processed_at, :utc_datetime_usec
    end
  end
end
