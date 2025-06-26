defmodule Public.Components.Subscription.PlanSelector do
  @moduledoc """
  Provides components for subscription plan selection and display.

  This module contains components for displaying subscription plans with different
  pricing intervals (monthly/yearly), highlighting popular plans, and showing
  plan features. It handles the display logic for current subscriptions and
  enables users to select new plans.
  """
  use Public, :html

  alias Core.Subscriptions.Plan

  @doc """
  Renders a reusable plan selector component with interval tabs.

  Displays a tabbed interface for selecting between monthly and yearly billing
  intervals, showing appropriate plan cards for each interval.

  ## Examples

      <.plan_selector plans={@plans} current_user={@current_user} current_subscription={@current_subscription} target={@myself} />
  """
  attr :plans, :map,
    required: true,
    doc: "Map of subscription plans returned by list_all_plans()."

  attr :current_user, :any, default: nil, doc: "The currently logged-in user, if any."
  attr :current_subscription, :any, default: nil, doc: "The user's current subscription, if any."
  attr :target, :any, default: nil, doc: "The target for phx-target, if any."
  attr :loading, :boolean, default: false, doc: "Whether the plan selection is loading."
  attr :proration_info, :map, default: %{}, doc: "Proration information for plan upgrades."

  def plan_selector(assigns) do
    ~H"""
    <div>
      <div role="tablist" class="tabs tabs-box w-fit mx-auto mt-4">
        <input
          type="radio"
          name="plan_interval_tabs"
          role="tab"
          class="tab"
          aria-label="Monthly"
          checked
        />
        <div role="tabpanel" class="tab-content p-4 mt-8">
          <div class="grid lg:grid-cols-3 gap-3 max-w-6xl mx-auto">
            <.plan_card
              :for={plan <- filter_plans(@plans, "month")}
              plan={plan}
              is_popular={plan.metadata["tier"] == "medium"}
              current_user={@current_user}
              current_subscription={@current_subscription}
              proration_info={@proration_info[plan.metadata["tier"]]}
              target={@target}
              loading={@loading}
            />
          </div>
        </div>

        <input type="radio" name="plan_interval_tabs" role="tab" class="tab" aria-label="Yearly" />
        <div role="tabpanel" class="tab-content p-4 mt-8">
          <div class="grid lg:grid-cols-3 gap-3 max-w-6xl mx-auto">
            <.plan_card
              :for={plan <- filter_plans(@plans, "year")}
              plan={plan}
              is_popular={plan.metadata["tier"] == "medium"}
              current_user={@current_user}
              current_subscription={@current_subscription}
              proration_info={@proration_info[plan.metadata["tier"]]}
              target={@target}
              loading={@loading}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single plan card with details and selection button.

  Displays plan information including name, price, features, and a button to
  select the plan. Highlights the card if it's marked as popular and shows
  a "Current Plan" indicator if applicable.
  """
  attr :plan, Plan, required: true
  attr :is_popular, :boolean, default: false
  attr :current_user, :any, default: nil
  attr :current_subscription, :any, default: nil
  attr :proration_info, :map, default: nil
  attr :target, :any, default: nil
  attr :loading, :boolean, default: false

  def plan_card(assigns) do
    ~H"""
    <div class={"card bg-base-100 shadow-lg" <> if(@is_popular, do: " border-2 border-primary lg:scale-110", else: " border border-base-300")}>
      <%= if @is_popular do %>
        <div class="absolute -top-3 right-4 badge badge-primary badge-lg">
          Most Popular
        </div>
      <% end %>

      <div class="card-body">
        <h2 class="card-title text-xl">{@plan.name}</h2>
        <div class="text-3xl font-bold">
          {format_price(@plan)}
          <span class="ml-1 text-sm font-normal text-base-content/70">/ {@plan.interval}</span>
        </div>

        <%= if @proration_info && @proration_info.is_upgrade && @plan.id == @proration_info.plan_id do %>
          <div class="alert alert-success mt-2">
            <.icon name="hero-check-circle" class="size-4" />
            <div>
              <p class="text-sm">
                Upgrade now and pay only
                <span class="font-bold">{@proration_info.prorated_price}</span>
                for the remainder of your billing period.
              </p>
              <p class="text-xs mt-1">
                ({@proration_info.percent_remaining}% of your billing period remaining)
              </p>
            </div>
          </div>
        <% end %>

        <p class="text-base-content/70 mt-2">
          {@plan.description}
        </p>

        <ul class="space-y-4 my-4">
          <%= for feature_key <- get_ordered_features(@plan) do %>
            <li class="flex items-start gap-2">
              <span class="text-primary">✓</span>
              <span class="text-sm">{Map.get(@plan.features, feature_key, "")}</span>
            </li>
          <% end %>
        </ul>

        <div class="card-actions justify-end mt-auto">
          <%= if @current_user && @current_subscription && @current_subscription.plan_id == @plan.id do %>
            <button class="btn btn-disabled w-full">Current Plan</button>
          <% else %>
            <button
              phx-click="select_plan"
              phx-value-plan-id={@plan.id}
              phx-target={@target}
              class="btn btn-primary w-full"
              disabled={@loading}
            >
              <%= if @loading do %>
                <span class="loading loading-spinner loading-sm"></span> Processing...
              <% else %>
                <%= if @proration_info && @proration_info.is_upgrade && @plan.id == @proration_info.plan_id do %>
                  Upgrade Now
                <% else %>
                  Select Plan
                <% end %>
              <% end %>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp filter_plans(plans_map, interval) when interval == "month" do
    plans_map
    |> Map.values()
    |> Enum.map(& &1.monthly)
    |> Enum.filter(&is_subscription_plan/1)
    |> Enum.sort_by(& &1.unit_amount)
  end

  defp filter_plans(plans_map, interval) when interval == "year" do
    plans_map
    |> Map.values()
    |> Enum.map(& &1.yearly)
    |> Enum.filter(&is_subscription_plan/1)
    |> Enum.sort_by(& &1.unit_amount)
  end

  # Helper function to safely check if a plan is a subscription plan
  defp is_subscription_plan(%Plan{product_type: :subscription}), do: true

  defp is_subscription_plan(%Plan{interval: interval}) when interval in ["month", "year"],
    do: true

  defp is_subscription_plan(_), do: false

  defp get_ordered_features(%Plan{features_order: features_order, features: _features})
       when is_list(features_order) do
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
        _ -> String.upcase(currency) <> " "
      end

    "#{currency_symbol}#{formatted_amount}"
  end

  defp format_price(%Plan{unit_amount: amount}), do: to_string(amount)
end
