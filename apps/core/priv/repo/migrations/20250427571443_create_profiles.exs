defmodule Core.Repo.Migrations.CreateProfiles do
  use Ecto.Migration

  def change do
    create table(:profiles) do
      add :first_name, :string
      add :last_name, :string
      add :bio, :text
      add :avatar_url, :string
      add :phone, :string
      add :location, :string
      add :website, :string
      add :social_links, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:profiles, [:user_id])
  end
end
