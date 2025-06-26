defmodule Core.Subscriptions.Plan do
  @moduledoc """
  Schema for subscription plans and single purchase products.

  This schema represents both subscription plans and single purchase products in the system,
  storing details such as pricing information, features, product type, and associated Stripe
  product and price IDs. Plans define the subscription options and single purchase products
  available to users and companies.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :name, :description, :unit_amount, :currency, :interval, :product_type, :metadata, :features, :features_order, :stripe_price_id, :stripe_product_id]}

  schema "plans" do
    field :name, :string
    field :description, :string
    field :unit_amount, :integer
    field :currency, :string
    field :interval, :string
    field :product_type, Ecto.Enum, values: [:subscription, :single_purchase], default: :subscription
    field :metadata, :map
    field :features, :map
    field :features_order, {:array, :string}, default: []
    field :stripe_price_id, :string
    field :stripe_product_id, :string

    timestamps()
  end

  @doc """
  Changeset function for creating or updating a plan.

  Validates that required fields are present. For subscription plans, interval is required.
  For single purchase products, interval should be nil.

  ## Parameters
    - plan: The plan struct to change
    - attrs: Map of attributes to apply to the plan
  """
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:name, :description, :unit_amount, :currency, :interval, :product_type, :metadata, :features, :features_order, :stripe_price_id, :stripe_product_id])
    |> validate_required([:name, :unit_amount, :currency, :product_type])
    |> validate_interval_based_on_product_type()
    |> validate_inclusion(:product_type, [:subscription, :single_purchase])
    |> validate_inclusion(:currency, ["usd", "eur", "gbp", "cad", "aud"])
  end

  defp validate_interval_based_on_product_type(changeset) do
    product_type = get_field(changeset, :product_type)
    interval = get_field(changeset, :interval)

    case product_type do
      :subscription ->
        changeset
        |> validate_required([:interval])
        |> validate_inclusion(:interval, ["month", "year", "week", "day"])

      :single_purchase ->
        if interval do
          add_error(changeset, :interval, "should be nil for single purchase products")
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
