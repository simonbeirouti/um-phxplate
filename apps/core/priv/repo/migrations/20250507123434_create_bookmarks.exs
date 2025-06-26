defmodule Core.Repo.Migrations.CreateBookmarks do
  use Ecto.Migration

  def change do
    create table(:bookmarks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :company_id, references(:companies, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:bookmarks, [:user_id, :company_id])
    create index(:bookmarks, [:user_id])
    create index(:bookmarks, [:company_id])
  end
end
