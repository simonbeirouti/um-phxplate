defmodule Core.Repo.Migrations.CreatePlatformSettings do
  use Ecto.Migration

  def change do
    create table(:platform_settings) do
      add :key, :string, null: false
      add :value, :boolean, null: false, default: false
      add :description, :string

      timestamps()
    end

    create unique_index(:platform_settings, [:key])

    # Insert default settings
    execute """
    INSERT INTO platform_settings (key, value, description, inserted_at, updated_at) VALUES
    ('subscriptions_enabled', true, 'Enable subscription plans', NOW(), NOW()),
    ('single_purchases_enabled', false, 'Enable single purchase products', NOW(), NOW())
    """, ""
  end
end
