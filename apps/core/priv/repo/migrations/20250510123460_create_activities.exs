defmodule Core.Repo.Migrations.CreateActivities do
  use Ecto.Migration

  def change do
    create table(:activities) do
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :integer, null: false
      add :changes, :map
      add :metadata, :map
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :company_id, references(:companies, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:activities, [:actor_id])
    create index(:activities, [:company_id])
    create index(:activities, [:entity_type, :entity_id])
  end
end
