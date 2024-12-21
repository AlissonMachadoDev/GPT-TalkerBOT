defmodule GptTalkerbot.Repo.Migrations.AddConstraintTelegramIdToGroup do
  use Ecto.Migration

  def change do
    create unique_index(:groups, [:telegram_id], name: :groups_telegram_id_index)
  end
end
