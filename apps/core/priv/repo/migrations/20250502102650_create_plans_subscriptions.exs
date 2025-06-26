defmodule Core.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    # Create product type enum
    execute "CREATE TYPE product_type AS ENUM ('subscription', 'single_purchase')"

    create table(:plans) do
      add :name, :string, null: false
      add :description, :string
      add :unit_amount, :integer, null: false
      add :currency, :string, null: false
      add :interval, :string # Made nullable for single purchase products
      add :product_type, :product_type, null: false, default: "subscription"
      add :metadata, :map
      add :features, :map
      add :features_order, {:array, :string}, default: [] # For drag-and-drop ordering
      add :stripe_price_id, :string
      add :stripe_product_id, :string

      timestamps()
    end

    create index(:plans, [:stripe_price_id])
    create index(:plans, [:stripe_product_id])
    create index(:plans, [:product_type])
    create index(:plans, [:interval])

    execute "CREATE TYPE subscription_status AS ENUM ('active', 'canceled', 'past_due', 'incomplete', 'trialing')"
    execute "CREATE TYPE paid_tier AS ENUM ('none', 'small', 'medium', 'large')"
    execute "CREATE TYPE purchase_status AS ENUM ('pending', 'completed', 'failed', 'refunded')"

    create table(:subscriptions) do
      add :stripe_customer_id, :string
      add :stripe_subscription_id, :string
      add :paid_tier, :paid_tier
      add :subscription_status, :subscription_status
      add :subscription_period_end, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, on_delete: :restrict)
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:subscriptions, [:user_id])
    create index(:subscriptions, [:plan_id])
    create index(:subscriptions, [:stripe_customer_id])
    create index(:subscriptions, [:stripe_subscription_id])

    # Table for single purchases
    create table(:purchases) do
      add :stripe_customer_id, :string
      add :stripe_payment_intent_id, :string
      add :stripe_charge_id, :string
      add :purchase_status, :purchase_status, null: false, default: "pending"
      add :amount, :integer, null: false
      add :currency, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, on_delete: :restrict), null: false # The single purchase product
      add :purchased_at, :utc_datetime
      add :metadata, :map # For storing additional purchase details

      timestamps()
    end

    create index(:purchases, [:user_id])
    create index(:purchases, [:plan_id])
    create index(:purchases, [:stripe_customer_id])
    create index(:purchases, [:stripe_payment_intent_id])
    create index(:purchases, [:purchase_status])
    create index(:purchases, [:purchased_at])
  end
end
