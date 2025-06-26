defmodule Core.Subscriptions.Subscription do
  @moduledoc """
  Schema for user subscriptions.

  This schema represents a subscription in the system, tracking the relationship
  between users and subscription plans. It stores details such as Stripe customer and
  subscription IDs, subscription status, and the paid tier level. The schema
  establishes associations with both users and plans.
  """
  use Ecto.Schema
  @derive {Jason.Encoder, only: [:id, :stripe_customer_id, :stripe_subscription_id, :paid_tier, :subscription_status, :subscription_period_end, :metadata, :user_id, :plan_id]}
  import Ecto.Changeset
  alias Core.Accounts.User
  alias Core.Subscriptions.Plan

  @subscription_statuses [:active, :canceled, :past_due, :incomplete, :trialing]
  @paid_tiers [:none, :small, :medium, :large]

  schema "subscriptions" do
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :paid_tier, Ecto.Enum, values: @paid_tiers
    field :subscription_status, Ecto.Enum, values: @subscription_statuses
    field :subscription_period_end, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :user, User
    belongs_to :plan, Plan

    timestamps()
  end

  @doc """
  Changeset for creating or updating a subscription.

  Validates required fields and ensures foreign key constraints are respected.
  Enforces unique constraint on the Stripe subscription ID.

  ## Parameters
    - subscription: The subscription struct to change
    - attrs: Map of attributes to apply to the subscription
  """
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :stripe_customer_id,
      :stripe_subscription_id,
      :paid_tier,
      :subscription_status,
      :subscription_period_end,
      :metadata,
      :user_id,
      :plan_id
    ])
    |> validate_required([
      :stripe_customer_id,
      :stripe_subscription_id,
      :paid_tier,
      :subscription_status,
      :user_id
    ])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:stripe_subscription_id)
  end
end
