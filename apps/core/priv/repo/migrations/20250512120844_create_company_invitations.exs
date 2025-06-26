defmodule Core.Repo.Migrations.CreateCompanyInvitations do
  use Ecto.Migration

  def change do
    create table(:company_invitations) do
      add :email, :string, null: false
      add :token, :string, null: false
      add :accepted_at, :utc_datetime
      add :company_id, references(:companies, on_delete: :delete_all), null: false
      add :inviter_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:company_invitations, [:company_id])
    create index(:company_invitations, [:inviter_id])
    create unique_index(:company_invitations, [:token])
    create unique_index(:company_invitations, [:company_id, :email])
  end
end
