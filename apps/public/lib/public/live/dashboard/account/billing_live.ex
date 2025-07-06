defmodule Public.Dashboard.Account.BillingLive do
  @moduledoc """
  LiveComponent for managing user subscription and billing information.

  This component provides UI for viewing current subscription details,
  changing plans, updating payment methods, and cancelling subscriptions.
  It integrates with Stripe for checkout and payment processing.
  """
  use Public, :live_component

  alias Core.Subscriptions
  import Public.Components.Subscription.SinglePurchaseSelector

  @doc """
  Updates the component with the user's subscription information.

  Retrieves the user's current subscription, available subscription plans,
  and single purchase products, then initializes the component state.
  """
  @impl true
  def update(%{platform_settings_updated: _msg}, socket) do
    # Handle platform settings updates only
    subscriptions_enabled = Subscriptions.subscriptions_enabled?()
    single_purchases_enabled = Subscriptions.single_purchases_enabled?()

    plans =
      if subscriptions_enabled do
        # Get the structured plans that plan_selector expects (with monthly/yearly per tier)
        all_plans = Subscriptions.list_all_plans()
        # Remove single_purchase key if it exists to avoid confusion
        Map.delete(all_plans, :single_purchase)
      else
        %{}
      end

    single_purchase_plans =
      if single_purchases_enabled do
        Subscriptions.list_plans_by_product_type(:single_purchase)
      else
        []
      end

    {:ok,
     socket
     |> assign(:subscriptions_enabled, subscriptions_enabled)
     |> assign(:single_purchases_enabled, single_purchases_enabled)
     |> assign(:plans, plans)
     |> assign(:single_purchase_plans, single_purchase_plans)}
  end

  @impl true
  def update(%{plans_updated: _msg}, socket) do
    # Handle plan updates only
    subscriptions_enabled =
      socket.assigns[:subscriptions_enabled] || Subscriptions.subscriptions_enabled?()

    single_purchases_enabled =
      socket.assigns[:single_purchases_enabled] || Subscriptions.single_purchases_enabled?()

    plans =
      if subscriptions_enabled do
        # Get the structured plans that plan_selector expects (with monthly/yearly per tier)
        all_plans = Subscriptions.list_all_plans()
        # Remove single_purchase key if it exists to avoid confusion
        Map.delete(all_plans, :single_purchase)
      else
        %{}
      end

    single_purchase_plans =
      if single_purchases_enabled do
        Subscriptions.list_plans_by_product_type(:single_purchase)
      else
        []
      end

    {:ok,
     socket
     |> assign(:plans, plans)
     |> assign(:single_purchase_plans, single_purchase_plans)}
  end

  @impl true
  def update(%{user: user} = assigns, socket) do
    subscription = Subscriptions.get_user_subscription(user.id)

    # Check platform settings to determine what to show
    subscriptions_enabled = Subscriptions.subscriptions_enabled?()
    single_purchases_enabled = Subscriptions.single_purchases_enabled?()

    plans =
      if subscriptions_enabled do
        # Get the structured plans that plan_selector expects (with monthly/yearly per tier)
        all_plans = Subscriptions.list_all_plans()
        # Remove single_purchase key if it exists to avoid confusion
        Map.delete(all_plans, :single_purchase)
      else
        %{}
      end

    single_purchase_plans =
      if single_purchases_enabled do
        Subscriptions.list_plans_by_product_type(:single_purchase)
      else
        []
      end

    # Check for scheduled downgrade in subscription metadata
    scheduled_downgrade =
      if subscription && subscription.metadata && subscription.metadata["scheduled_plan_change"] do
        plan_id = subscription.metadata["scheduled_plan_change"]["plan_id"]
        effective_date_str = subscription.metadata["scheduled_plan_change"]["effective_date"]

        # Parse the effective_date string into a DateTime
        effective_date =
          case DateTime.from_iso8601(effective_date_str) do
            {:ok, datetime, _offset} ->
              datetime

            _ ->
              # If parsing fails, use the subscription period end as fallback
              subscription.subscription_period_end
          end

        new_plan = Subscriptions.get_plan!(plan_id)

        %{
          current_plan: subscription.plan.name,
          new_plan: new_plan.name,
          effective_date: effective_date
        }
      else
        nil
      end

    # Load subscription activities
    subscription_activities =
      if subscription do
        user_subscription_activities = Core.Tracking.get_user_subscription_activities(user.id, 20)

        subscription_entity_activities =
          Core.Tracking.get_subscription_activities(subscription.id, 20)

        # Combine and sort activities by date
        (user_subscription_activities ++ subscription_entity_activities)
        |> Enum.sort_by(& &1.inserted_at, :desc)
        |> Enum.take(20)
      else
        Core.Tracking.get_user_subscription_activities(user.id, 20)
      end

    # Calculate proration information for each plan if user has an active subscription
    proration_info = calculate_proration_info(subscription, plans)

    socket =
      socket
      |> assign(assigns)
      |> assign(:subscription, subscription)
      |> assign(:plans, plans)
      |> assign(:single_purchase_plans, single_purchase_plans)
      |> assign(:loading, false)
      |> assign(:loading_payment, false)
      |> assign(:checkout_url, nil)
      |> assign(:show_cancel_confirm, false)
      |> assign(:proration_info, proration_info)
      |> assign(:scheduled_downgrade, scheduled_downgrade)
      |> assign(:subscriptions_enabled, subscriptions_enabled)
      |> assign(:single_purchases_enabled, single_purchases_enabled)
      |> assign(:subscription_activities, subscription_activities)
      |> assign(:dialog_drawer_mode, "dialog")

    {:ok, socket}
  end

  # Helper function to calculate proration information
  defp calculate_proration_info(nil, _plans), do: %{}
  defp calculate_proration_info(%{subscription_status: :canceled}, _plans), do: %{}
  defp calculate_proration_info(_subscription, plans) when map_size(plans) == 0, do: %{}

  defp calculate_proration_info(subscription, plans) do
    current_plan = subscription.plan

    # Get today's date and the end of the billing period
    today = Date.utc_today()
    period_end = DateTime.to_date(subscription.subscription_period_end)

    # Calculate days remaining in billing period
    total_days_in_period =
      case current_plan.interval do
        # Approximate for simplicity
        "month" -> 30
        "year" -> 365
        _ -> 30
      end

    days_remaining = Date.diff(period_end, today)
    days_used = total_days_in_period - days_remaining

    # Calculate percentage of period remaining
    percent_remaining = Float.round(days_remaining / total_days_in_period * 100, 1)

    # For each plan tier, calculate the prorated cost if it's an upgrade
    Enum.reduce(plans, %{}, fn {tier, tier_plans}, acc ->
      # Ensure tier_plans is a map with the expected structure
      if is_map(tier_plans) do
        # Get the plan with the same interval as the current subscription
        comparable_plan = Map.get(tier_plans, String.to_atom(current_plan.interval))

        if comparable_plan && comparable_plan.unit_amount > current_plan.unit_amount do
          # This is an upgrade - calculate prorated amount
          price_difference = comparable_plan.unit_amount - current_plan.unit_amount
          prorated_cost = Float.round(price_difference * days_remaining / total_days_in_period, 2)

          # Format for display
          formatted_full = format_currency(comparable_plan.unit_amount, comparable_plan.currency)
          formatted_prorated = format_currency(trunc(prorated_cost), comparable_plan.currency)

          Map.put(acc, tier, %{
            is_upgrade: true,
            plan_id: comparable_plan.id,
            full_price: formatted_full,
            prorated_price: formatted_prorated,
            percent_remaining: percent_remaining,
            days_remaining: days_remaining,
            days_used: days_used
          })
        else
          # Not an upgrade or no comparable plan
          acc
        end
      else
        # Skip if tier_plans is not in the expected format
        acc
      end
    end)
  end

  # Helper function to format currency
  defp format_currency(amount, currency) do
    # Convert cents to dollars/euros/etc
    decimal_amount = amount / 100.0

    case currency do
      "usd" -> "$#{:erlang.float_to_binary(decimal_amount, decimals: 2)}"
      "eur" -> "€#{:erlang.float_to_binary(decimal_amount, decimals: 2)}"
      _ -> "#{:erlang.float_to_binary(decimal_amount, decimals: 2)} #{String.upcase(currency)}"
    end
  end

  # Helper function to filter monthly plans
  defp filter_monthly_plans(plans_map) do
    plans_map
    |> Map.values()
    |> Enum.map(& &1.monthly)
    |> Enum.filter(&is_subscription_plan/1)
    |> Enum.sort_by(& &1.unit_amount)
  end

  # Helper function to filter yearly plans
  defp filter_yearly_plans(plans_map) do
    plans_map
    |> Map.values()
    |> Enum.map(& &1.yearly)
    |> Enum.filter(&is_subscription_plan/1)
    |> Enum.sort_by(& &1.unit_amount)
  end

  # Helper function to safely check if a plan is a subscription plan
  defp is_subscription_plan(%{product_type: :subscription}), do: true
  defp is_subscription_plan(%{interval: interval}) when interval in ["month", "year"], do: true
  defp is_subscription_plan(_), do: false

  # Plan card component
  attr :plan, :any, required: true
  attr :current_user, :any, default: nil
  attr :current_subscription, :any, default: nil
  attr :target, :any, default: nil
  attr :loading, :boolean, default: false

  def plan_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg border border-base-300">
      <div class="card-body">
        <h2 class="card-title text-xl">{@plan.name}</h2>
        <div class="text-3xl font-bold">
          {format_plan_price(@plan)}
          <span class="ml-1 text-sm font-normal">/ {@plan.interval}</span>
        </div>
        <p class="text-base-content/70 mt-2">
          {@plan.description}
        </p>

        <%= if @plan.features && map_size(@plan.features) > 0 do %>
          <ul class="space-y-4 mt-4">
            <%= for {_feature_key, feature_value} <- @plan.features do %>
              <li class="flex items-start gap-2">
                <span class="text-primary">✓</span>
                {feature_value}
              </li>
            <% end %>
          </ul>
        <% end %>

        <div class="card-actions justify-end mt-6">
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
                Select Plan
              <% end %>
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp format_plan_price(%{unit_amount: amount, currency: currency}) when is_integer(amount) do
    formatted_amount = amount / 100

    currency_symbol =
      case currency do
        "usd" -> "$"
        _ -> String.upcase(currency) <> " "
      end

    "#{currency_symbol}#{formatted_amount}"
  end

  defp format_plan_price(%{unit_amount: amount}), do: to_string(amount)

  @impl true
  def handle_event("set_screen_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :dialog_drawer_mode, mode)}
  end

  def handle_event("update_payment_method", _, socket) do
    socket = assign(socket, :loading_payment, true)
    subscription = socket.assigns.subscription

    if subscription && subscription.stripe_subscription_id do
      # Create a Stripe portal session for managing payment methods
      case Stripe.BillingPortal.Session.create(%{
             customer: subscription.stripe_customer_id,
             return_url: "#{Application.get_env(:public, :base_url)}/dashboard/account"
           }) do
        {:ok, %{url: portal_url}} ->
          {:noreply,
           socket
           |> assign(:loading_payment, false)
           |> redirect(external: portal_url)}

        {:error, _error} ->
          {:noreply,
           socket
           |> assign(:loading_payment, false)
           |> put_flash(:error, "Could not access payment settings. Please try again later.")}
      end
    else
      {:noreply,
       socket
       |> assign(:loading_payment, false)
       |> put_flash(:error, "You need an active subscription to update payment methods.")}
    end
  end

  def handle_event("select_plan", %{"plan-id" => plan_id}, socket) do
    user = socket.assigns.user
    plan = Subscriptions.get_plan!(plan_id)

    socket = socket |> assign(:loading, true)

    case Subscriptions.change_subscription_plan(user, plan) do
      # Handle scheduled downgrade - no redirect needed
      {:ok, %{scheduled_downgrade: true} = downgrade_info} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:show_plans_modal, false)
         |> assign(:scheduled_downgrade, downgrade_info)
         |> put_flash(
           :info,
           "Your subscription will be downgraded to #{downgrade_info.new_plan} at the end of your current billing period (#{Calendar.strftime(downgrade_info.effective_date, "%B %d, %Y")})."
         )}

      # Handle upgrades and new subscriptions - redirect to Stripe checkout
      {:ok, %Stripe.Session{} = session} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:checkout_url, session.url)
         |> redirect(external: session.url)}

      {:error, _error} ->
        # Handle error
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:show_plans_modal, false)
         |> put_flash(:error, "Failed to complete payment. Please try again later.")}
    end
  end

  def handle_event("show_cancel_confirmation", _, socket) do
    {:noreply, assign(socket, :show_cancel_confirm, true)}
  end

  def handle_event("cancel_confirmation", _, socket) do
    {:noreply, assign(socket, :show_cancel_confirm, false)}
  end

  def handle_event("confirm_cancel_subscription", _, socket) do
    case Core.Subscriptions.cancel_subscription(socket.assigns.user) do
      {:ok, _subscription} ->
        send(
          self(),
          {:flash_msg, :info,
           "Your subscription has been cancelled and will end at the end of the billing period."}
        )

        {:noreply, assign(socket, :show_cancel_confirm, false)}

      {:error, _reason} ->
        send(
          self(),
          {:flash_msg, :error,
           "There was an error cancelling your subscription. Please try again."}
        )

        {:noreply, socket}
    end
  end

  def handle_event("reactivate_subscription", _, socket) do
    case Core.Subscriptions.admin_update_subscription_status(
           socket.assigns.subscription,
           :active,
           socket.assigns.user
         ) do
      {:ok, updated_subscription} ->
        {:noreply,
         socket
         |> assign(:subscription, updated_subscription)
         |> put_flash(
           :info,
           "Your subscription has been reactivated and will continue to bill normally."
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "There was an error reactivating your subscription. Please try again."
         )}
    end
  end

  def handle_event("purchase_product", %{"product-id" => product_id}, socket) do
    user = socket.assigns.user
    product = Subscriptions.get_plan!(product_id)

    socket = socket |> assign(:loading, true)

    case Subscriptions.create_single_purchase_checkout_session(user, product) do
      {:ok, %Stripe.Session{url: checkout_url}} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:show_plans_modal, false)
         |> redirect(external: checkout_url)}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:show_plans_modal, false)
         |> put_flash(:error, "Failed to process purchase. Please try again later.")}
    end
  end

  @doc """
  Renders the subscription management UI.

  Displays the current subscription details, options to change plans,
  update payment methods, and cancel or reactivate subscriptions.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if not @subscriptions_enabled and not @single_purchases_enabled do %>
        <div class="card bg-base-100 shadow-lg">
          <div class="card-body text-center">
            <.icon name="hero-information-circle" class="h-12 w-12 mx-auto text-base-content/50 mb-4" />
            <h3 class="card-title justify-center text-xl mb-2">Billing Not Available</h3>
            <p class="text-base-content/70">
              Subscription and purchase options are currently disabled.
              Please contact support for assistance.
            </p>
          </div>
        </div>
      <% else %>
        <%= if @subscription do %>
          <div class="card bg-base-100 shadow-lg">
            <div class="card-body">
              <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
                <div class="flex-1">
                  <h3 class="card-title text-xl mb-4">
                    Current Plan: {@subscription.plan.name}
                  </h3>
                  <div class="space-y-2">
                    <div class="flex items-center gap-2">
                      <span class="text-base-content/70">Status:</span>
                      <div class={
                        case @subscription.subscription_status do
                          :active -> "badge badge-success"
                          :canceled -> "badge badge-error"
                          :past_due -> "badge badge-warning"
                          :incomplete -> "badge badge-warning"
                          :trialing -> "badge badge-info"
                        end
                      }>
                        {String.capitalize(to_string(@subscription.subscription_status))}
                      </div>
                    </div>
                    <p class="text-base-content/70">
                      Billing Frequency: {String.capitalize(@subscription.plan.interval)}ly
                    </p>

                    <%= if @scheduled_downgrade do %>
                      <div class="alert alert-warning mt-4">
                        <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
                        <div>
                          <h4 class="font-semibold">Heads up!</h4>
                          <p class="text-sm">
                            Your subscription will be downgraded from
                            <span class="font-semibold">{@scheduled_downgrade.current_plan}</span>
                            to <span class="font-semibold">{@scheduled_downgrade.new_plan}</span>
                            on {Calendar.strftime(@scheduled_downgrade.effective_date, "%B %d, %Y")}.
                          </p>
                        </div>
                      </div>
                    <% end %>

                    <%= if @subscription.subscription_status == :canceled do %>
                      <div class="alert alert-error mt-4">
                        <.icon name="hero-exclamation-circle" class="h-6 w-6" />
                        <div>
                          <p class="font-semibold">
                            Your subscription will end on {Calendar.strftime(
                              @subscription.subscription_period_end,
                              "%B %d, %Y"
                            )}
                          </p>
                          <p class="text-sm">
                            Choose a new plan to continue your subscription after this date.
                          </p>
                        </div>
                      </div>
                    <% else %>
                      <p class="text-base-content/70">
                        Next billing date: {Calendar.strftime(
                          @subscription.subscription_period_end,
                          "%B %d, %Y"
                        )}
                      </p>
                    <% end %>
                  </div>
                </div>
                <div class="flex-shrink-0">
                  <%= if @subscription.subscription_status == :canceled do %>
                    <button
                      phx-click="reactivate_subscription"
                      phx-target={@myself}
                      class="btn btn-success"
                    >
                      Reactivate Current Plan
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <%= if @subscription.subscription_status != :canceled do %>
            <div class="card bg-base-100 shadow-lg">
              <div class="card-body">
                <h3 class="card-title text-lg mb-4">Cancel Subscription</h3>
                <p class="text-base-content/70 mb-4">
                  Cancel your current subscription. This will take effect at the end of your billing period ({Calendar.strftime(
                    @subscription.subscription_period_end,
                    "%B %d, %Y"
                  )}).
                </p>
                <div class="card-actions">
                  <%= if @show_cancel_confirm do %>
                    <div class="flex gap-3">
                      <button
                        phx-click="confirm_cancel_subscription"
                        phx-target={@myself}
                        class="btn btn-error"
                      >
                        Confirm Cancellation
                      </button>
                      <button
                        phx-click="cancel_confirmation"
                        phx-target={@myself}
                        class="btn btn-outline"
                      >
                        Keep Subscription
                      </button>
                    </div>
                  <% else %>
                    <button
                      phx-click="show_cancel_confirmation"
                      phx-target={@myself}
                      class="btn btn-error"
                    >
                      Cancel Subscription
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @subscriptions_enabled and map_size(@plans) > 0 do %>
            <div class="card bg-base-100 shadow-lg">
              <div class="card-body">
                <h3 class="card-title text-lg mb-6">Subscription Plans</h3>

    <!-- Monthly Plans -->
                <div class="mb-8">
                  <h4 class="text-md font-semibold text-base-content mb-4">Monthly</h4>
                  <div class="grid lg:grid-cols-3 gap-4">
                    <%= for plan <- filter_monthly_plans(@plans) do %>
                      <.plan_card
                        plan={plan}
                        current_user={@user}
                        current_subscription={@subscription}
                        target={@myself}
                        loading={@loading}
                      />
                    <% end %>
                  </div>
                </div>

    <!-- Yearly Plans -->
                <div class="mb-8">
                  <h4 class="text-md font-semibold text-base-content mb-4">Yearly</h4>
                  <div class="grid lg:grid-cols-3 gap-4">
                    <%= for plan <- filter_yearly_plans(@plans) do %>
                      <.plan_card
                        plan={plan}
                        current_user={@user}
                        current_subscription={@subscription}
                        target={@myself}
                        loading={@loading}
                      />
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @single_purchases_enabled and length(@single_purchase_plans) > 0 do %>
            <div class="card bg-base-100 shadow-lg">
              <div class="card-body">
                <.single_purchase_selector
                  products={@single_purchase_plans}
                  current_user={@user}
                  target={@myself}
                  loading={@loading}
                  title="Single Purchase"
                  description="Purchase additional products and services to enhance your experience."
                />
              </div>
            </div>
          <% end %>
        <% else %>
          <%= if @subscriptions_enabled and map_size(@plans) > 0 do %>
            <div class="card bg-base-100 shadow-lg">
              <div class="card-body">
                <h3 class="card-title text-lg mb-6">Choose Your Plan</h3>

    <!-- Monthly Plans -->
                <div class="mb-8">
                  <h4 class="text-md font-semibold text-base-content mb-4">Monthly</h4>
                  <div class="grid lg:grid-cols-3 gap-4">
                    <%= for plan <- filter_monthly_plans(@plans) do %>
                      <.plan_card
                        plan={plan}
                        current_user={@user}
                        current_subscription={@subscription}
                        target={@myself}
                        loading={@loading}
                      />
                    <% end %>
                  </div>
                </div>

    <!-- Yearly Plans -->
                <div class="mb-8">
                  <h4 class="text-md font-semibold text-base-content mb-4">Yearly</h4>
                  <div class="grid lg:grid-cols-3 gap-4">
                    <%= for plan <- filter_yearly_plans(@plans) do %>
                      <.plan_card
                        plan={plan}
                        current_user={@user}
                        current_subscription={@subscription}
                        target={@myself}
                        loading={@loading}
                      />
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @single_purchases_enabled and length(@single_purchase_plans) > 0 do %>
            <div class="card bg-base-100 shadow-lg">
              <div class="card-body">
                <.single_purchase_selector
                  products={@single_purchase_plans}
                  current_user={@user}
                  target={@myself}
                  loading={@loading}
                  title="Single Purchase"
                  description="Purchase products without a subscription."
                />
              </div>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end
end
