defmodule Core.Repo.Migrations.CreateFeatureRequests do
  use Ecto.Migration

  def change do
    create table(:feature_requests) do
      add :priority_rating, :integer
      add :feasibility_rating, :integer
      add :feature_description, :text
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:feature_requests, [:user_id])
  end
end
