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
  attr :selected_interval, :string, default: "month", doc: "Currently selected billing interval."

  def plan_selector(assigns) do
    ~H"""
    <div class="w-full">
      <!-- Centered tabs -->
      <div class="flex justify-center mb-8 md:mb-16">
        <div class="tabs tabs-box bg-base-200">
          <button
            class={"tab" <> if(@selected_interval == "month", do: " tab-active", else: "")}
            phx-click="change_interval"
            phx-value-interval="month"
            phx-target={@target}
          >
            Monthly
          </button>
          <button
            class={"tab" <> if(@selected_interval == "year", do: " tab-active", else: "")}
            phx-click="change_interval"
            phx-value-interval="year"
            phx-target={@target}
          >
            Yearly
          </button>
        </div>
      </div>

      <!-- Plans content -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-1 max-w-7xl mx-auto px-4">
        <.plan_card
          :for={plan <- filter_plans(@plans, @selected_interval)}
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
    <div class={"card bg-base-100 shadow-xl relative" <> if(@is_popular, do: " border-2 border-primary transform md:scale-105 md:-mt-2 z-10", else: " border border-base-300")}>
      <%= if @is_popular do %>
        <div class="absolute -top-4 left-1/2 transform -translate-x-1/2 z-20 w-2/3">
          <div class="badge badge-primary badge-lg px-4 py-2 text-white font-semibold w-full">
            Most Popular
          </div>
        </div>
      <% end %>

      <div class="card-body p-8">
        <div class="text-left mb-6">
          <h2 class="card-title text-2xl font-bold">{@plan.name}</h2>
          <div class="text-4xl font-bold mt-4 text-primary">
            {format_price(@plan)}
            <span class="text-lg font-normal text-base-content/70">/ {@plan.interval}</span>
          </div>
          <p class="text-base-content/70 mt-3 text-lg">
            {@plan.description}
          </p>
        </div>

        <%= if @proration_info && @proration_info.is_upgrade && @plan.id == @proration_info.plan_id do %>
          <div class="alert alert-success mb-6">
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

        <ul class="space-y-2 flex-grow">
          <%= for feature_key <- get_ordered_features(@plan) do %>
            <li class="flex items-center gap-3">
              <div class="flex-shrink-0">
                <.icon name="hero-check" class="size-5 text-success" />
              </div>
              <span class="text-base-content">{Map.get(@plan.features, feature_key, "")}</span>
            </li>
          <% end %>
        </ul>

        <div class="card-actions mt-8">
          <%= if @current_user && @current_subscription && @current_subscription.plan_id == @plan.id do %>
            <button class="btn btn-disabled w-full">Current Plan</button>
          <% else %>
            <button
              phx-click="select_plan"
              phx-value-plan-id={@plan.id}
              phx-target={@target}
              class={"btn w-full" <> if(@is_popular, do: " btn-primary", else: " btn-outline btn-primary")}
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
