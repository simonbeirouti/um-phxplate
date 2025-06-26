defmodule Public.Components.Subscription.SinglePurchaseSelector do
  @moduledoc """
  Component for displaying and selecting single purchase products.

  This component handles the display of one-time purchase products
  separately from subscription plans, providing a cleaner separation
  of concerns.
  """
  use Public, :html

  alias Core.Subscriptions.Plan

  @doc """
  Renders a grid of single purchase products.

  Displays available one-time purchase products in a grid layout
  with product details and purchase buttons.

  ## Examples

      <.single_purchase_selector products={@single_purchase_plans} current_user={@current_user} target={@myself} />
  """
  attr :products, :list, required: true, doc: "List of single purchase products."
  attr :current_user, :any, default: nil, doc: "The currently logged-in user, if any."
  attr :target, :any, default: nil, doc: "The target for phx-target, if any."
  attr :loading, :boolean, default: false, doc: "Whether the purchase is loading."
  attr :title, :string, default: "One-Time Purchases", doc: "Title for the section."

  attr :description, :string,
    default: "Purchase products and services without a subscription.",
    doc: "Description for the section."

  attr :class, :string, default: "", doc: "Additional CSS classes."

  def single_purchase_selector(assigns) do
    ~H"""
    <div class={["space-y-6", @class]}>
      <div class="text-center">
        <h2 class="text-2xl font-bold">{@title}</h2>
        <p class="mt-2 text-base-content/70">{@description}</p>
      </div>

      <%= if Enum.empty?(@products) do %>
        <div class="text-center py-12">
          <div class="card bg-base-100 border border-base-300 p-8 max-w-md mx-auto">
            <div class="card-body text-center">
              <.icon name="hero-shopping-cart" class="h-12 w-12 mx-auto text-base-content/40 mb-4" />
              <h3 class="card-title justify-center text-lg mb-2">No Products Available</h3>
              <p class="text-base-content/70">
                There are currently no one-time purchase products available.
                Check back later for new offerings.
              </p>
            </div>
          </div>
        </div>
      <% else %>
        <div class="grid lg:grid-cols-3 gap-6 max-w-6xl mx-auto">
          <.single_purchase_card
            :for={product <- @products}
            product={product}
            current_user={@current_user}
            target={@target}
            loading={@loading}
          />
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a single purchase product card.

  Displays product information including name, price, features, and a button to
  purchase the product. Used for one-time purchases like templates, services, etc.
  """
  attr :product, Plan, required: true
  attr :current_user, :any, default: nil
  attr :target, :any, default: nil
  attr :loading, :boolean, default: false

  def single_purchase_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg border border-base-300">
      <div class="card-body">
        <h2 class="card-title text-xl">{@product.name}</h2>
        <div class="text-3xl font-bold text-primary">
          {format_price(@product)}
          <span class="ml-1 text-sm font-normal text-base-content/70">one-time</span>
        </div>

        <p class="text-base-content/70 mt-2">
          {@product.description}
        </p>

        <%= if @product.features && map_size(@product.features) > 0 do %>
          <ul class="space-y-3 my-4">
            <%= for feature_key <- get_ordered_features(@product) do %>
              <li class="flex items-start gap-2">
                <span class="text-success">✓</span>
                <span class="text-sm">{Map.get(@product.features, feature_key, "")}</span>
              </li>
            <% end %>
          </ul>
        <% end %>

        <div class="card-actions justify-end mt-auto">
          <button
            phx-click="purchase_product"
            phx-value-product-id={@product.id}
            phx-target={@target}
            class="btn btn-primary w-full"
            disabled={@loading}
          >
            <%= if @loading do %>
              <span class="loading loading-spinner loading-sm"></span>
              Processing...
            <% else %>
              Purchase Now
            <% end %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp get_ordered_features(%Plan{features_order: features_order}) when is_list(features_order) do
    features_order
  end

  defp get_ordered_features(%Plan{features: features}) when is_map(features) do
    Map.keys(features) |> Enum.sort()
  end

  defp get_ordered_features(_), do: []

  defp format_price(%Plan{unit_amount: amount, currency: currency}) when is_integer(amount) do
    formatted_amount = amount / 100

    currency_symbol =
      case currency do
        "usd" -> "$"
        "eur" -> "€"
        _ -> String.upcase(currency) <> " "
      end

    "#{currency_symbol}#{:erlang.float_to_binary(formatted_amount, decimals: 2)}"
  end

  defp format_price(%Plan{unit_amount: amount}), do: to_string(amount)
end
