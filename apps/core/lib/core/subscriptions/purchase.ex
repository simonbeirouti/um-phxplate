defmodule Core.Subscriptions.Purchase do
  @moduledoc """
  Schema for single purchase orders.

  This schema represents a single purchase transaction in the system, storing details
  such as payment information, status, and associated Stripe payment intent and charge IDs.
  Purchases are linked to both users and the single purchase products they bought.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :stripe_customer_id, :stripe_payment_intent_id, :stripe_charge_id, :purchase_status, :amount, :currency, :user_id, :plan_id, :purchased_at, :metadata]}

  schema "purchases" do
    field :stripe_customer_id, :string
    field :stripe_payment_intent_id, :string
    field :stripe_charge_id, :string
    field :purchase_status, Ecto.Enum, values: [:pending, :completed, :failed, :refunded], default: :pending
    field :amount, :integer
    field :currency, :string
    field :purchased_at, :utc_datetime
    field :metadata, :map

    belongs_to :user, Core.Accounts.User
    belongs_to :plan, Core.Subscriptions.Plan

    timestamps()
  end

  @doc """
  Changeset function for creating or updating a purchase.

  Validates that required fields are present and that the associated plan
  is a single purchase product.

  ## Parameters
    - purchase: The purchase struct to change
    - attrs: Map of attributes to apply to the purchase
  """
  def changeset(purchase, attrs) do
    purchase
    |> cast(attrs, [:stripe_customer_id, :stripe_payment_intent_id, :stripe_charge_id, :purchase_status, :amount, :currency, :user_id, :plan_id, :purchased_at, :metadata])
    |> validate_required([:purchase_status, :amount, :currency, :user_id, :plan_id])
    |> validate_inclusion(:purchase_status, [:pending, :completed, :failed, :refunded])
    |> validate_inclusion(:currency, ["usd", "eur", "gbp", "cad", "aud"])
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:plan_id)
  end

  @doc """
  Changeset for updating purchase status.
  """
  def status_changeset(purchase, attrs) do
    purchase
    |> cast(attrs, [:purchase_status, :purchased_at, :stripe_charge_id, :metadata])
    |> validate_inclusion(:purchase_status, [:pending, :completed, :failed, :refunded])
  end
end
