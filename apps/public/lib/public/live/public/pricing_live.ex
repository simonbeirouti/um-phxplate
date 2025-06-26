defmodule Public.PricingLive do
  @moduledoc """
  LiveView for displaying subscription plans and pricing information.

  This view lists available subscription plans for users to choose from, displaying
  pricing information and features for each plan. It handles plan selection differently
  based on authentication status - redirecting unauthenticated users to registration
  and authenticated users to checkout. The view fetches the current user's subscription
  status to highlight their current plan.
  """
  use Public, :live_view
  alias Core.Subscriptions
  import Public.Components.Subscription.PlanSelector
  import Public.Components.Subscription.SinglePurchaseSelector
  alias Public.PageMeta

  @doc """
  Initializes the LiveView with available plans and user subscription info.

  Fetches all subscription plans and single purchase products from the database
  and checks if the current user has an active subscription. Sets page metadata
  with title and description.
  """
  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to platform settings changes and plan changes for live updates
    if connected?(socket) do
      Core.PubSub.DataSync.subscribe("platform_settings", "all")
      Core.PubSub.DataSync.subscribe("plans", "all")
    end

    # Check platform settings to determine what to show
    subscriptions_enabled = Subscriptions.subscriptions_enabled?()
    single_purchases_enabled = Subscriptions.single_purchases_enabled?()

    # Get subscription plans only if enabled - use proper structure for plan_selector
    plans = if subscriptions_enabled do
      # Get the structured plans that plan_selector expects (with monthly/yearly per tier)
      all_plans = Subscriptions.list_all_plans()
      # Remove single_purchase key if it exists to avoid confusion
      Map.delete(all_plans, :single_purchase)
    else
      %{}
    end

    # Get single purchase products only if enabled
    single_purchase_plans = if single_purchases_enabled do
      Subscriptions.list_plans_by_product_type(:single_purchase)
    else
      []
    end

    # Fetch subscription if a user is logged in (assigns.current_user is set by auth hooks)
    current_user = socket.assigns.current_user

    subscription =
      if current_user do
        Subscriptions.get_user_subscription(current_user.id)
      else
        nil
      end

    {:ok,
     socket
     |> PageMeta.assign_metadata(
       title: "Pricing",
       description: "Choose the right plan for you",
       url: "/pricing"
     )
     |> assign(
       plans: plans,
       single_purchase_plans: single_purchase_plans,
       current_subscription: subscription,
       loading: false,
       subscriptions_enabled: subscriptions_enabled,
       single_purchases_enabled: single_purchases_enabled
     )}
  end

  @doc """
  Renders the pricing page with plan selection component.

  Displays a heading and description followed by the plan selection component
  which shows all available subscription plans and single purchase products
  with their features and pricing.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <%= if @subscriptions_enabled or @single_purchases_enabled do %>
      <.header_section title="Pricing" subtitle="Choose the right plan for you" />

      <%= if @subscriptions_enabled do %>
        <div class="mx-auto max-w-7xl mt-12 mb-24">
          <.plan_selector
            plans={@plans}
            current_user={@current_user}
            current_subscription={@current_subscription}
            loading={@loading}
          />
        </div>
      <% end %>

      <%= if @single_purchases_enabled and length(@single_purchase_plans) > 0 do %>
        <div class="mx-auto max-w-7xl mt-12 mb-24 p-4">
          <.single_purchase_selector
            products={@single_purchase_plans}
            current_user={@current_user}
            loading={@loading}
          />
        </div>
      <% end %>

      <.cta />
    <% else %>
      <div class="mx-auto max-w-4xl p-4 text-center">
        <div class="bg-gray-50 border border-gray-200 rounded-lg p-12">
          <.icon name="hero-info" class="h-12 w-12 mx-auto text-gray-400 mb-4" />
          <h2 class="text-2xl font-bold text-gray-900 mb-4">Pricing coming soon!</h2>
          <p class="text-gray-600 mb-6">
            Pricing and subscription options are currently not available.
            Please check back later or contact support for more information.
          </p>
          <.link navigate={~p"/contact"}>
            <button class="btn btn-primary">Contact Support</button>
          </.link>
        </div>
      </div>
    <% end %>
    """
  end

  @impl true
  def handle_event("select_plan", %{"plan-id" => plan_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        # User not logged in: redirect to register with plan_id as URL parameter
        {:noreply, push_navigate(socket, to: ~p"/register?plan_id=#{plan_id}")}

      user ->
        # User logged in: redirect directly to Stripe checkout instead of the dashboard
        socket = assign(socket, :loading, true)
        plan = Subscriptions.get_plan!(plan_id)

        case Subscriptions.change_subscription_plan(user, plan) do
          {:ok, %Stripe.Session{url: checkout_url}} ->
            # Redirect to Stripe checkout
            {:noreply, redirect(socket, external: checkout_url)}

          {:error, _error} ->
            # Handle error
            {:noreply,
             socket
             |> assign(:loading, false)
             |> put_flash(:error, "Failed to process subscription. Please try again later.")}
        end
    end
  end

  @impl true
  def handle_event("purchase_product", %{"product-id" => product_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        # User not logged in: redirect to register
        {:noreply, push_navigate(socket, to: ~p"/register")}

      user ->
        # User logged in: redirect to Stripe checkout for single purchase
        socket = assign(socket, :loading, true)
        product = Subscriptions.get_plan!(product_id)

        case Subscriptions.create_single_purchase_checkout_session(user, product) do
          {:ok, %Stripe.Session{url: checkout_url}} ->
            # Redirect to Stripe checkout
            {:noreply, redirect(socket, external: checkout_url)}

          {:error, _error} ->
            # Handle error
            {:noreply,
             socket
             |> assign(:loading, false)
             |> put_flash(:error, "Failed to process purchase. Please try again later.")}
        end
    end
  end

  @impl true
  def handle_info({:updated, %{type: :platform_setting}}, socket) do
    # Reload platform settings and update the view
    subscriptions_enabled = Subscriptions.subscriptions_enabled?()
    single_purchases_enabled = Subscriptions.single_purchases_enabled?()

    # Get subscription plans only if enabled - use proper structure for plan_selector
    plans = if subscriptions_enabled do
      # Get the structured plans that plan_selector expects (with monthly/yearly per tier)
      all_plans = Subscriptions.list_all_plans()
      # Remove single_purchase key if it exists to avoid confusion
      Map.delete(all_plans, :single_purchase)
    else
      %{}
    end

    # Get single purchase products only if enabled
    single_purchase_plans = if single_purchases_enabled do
      Subscriptions.list_plans_by_product_type(:single_purchase)
    else
      []
    end

    {:noreply,
     socket
     |> assign(:subscriptions_enabled, subscriptions_enabled)
     |> assign(:single_purchases_enabled, single_purchases_enabled)
     |> assign(:plans, plans)
     |> assign(:single_purchase_plans, single_purchase_plans)}
  end

  def handle_info({:created, %{type: :plan}}, socket) do
    # Reload plans when a new plan is created
    subscriptions_enabled = socket.assigns.subscriptions_enabled
    single_purchases_enabled = socket.assigns.single_purchases_enabled

    # Get subscription plans only if enabled - use proper structure for plan_selector
    plans = if subscriptions_enabled do
      # Get the structured plans that plan_selector expects (with monthly/yearly per tier)
      all_plans = Subscriptions.list_all_plans()
      # Remove single_purchase key if it exists to avoid confusion
      Map.delete(all_plans, :single_purchase)
    else
      %{}
    end

    # Get single purchase products only if enabled
    single_purchase_plans = if single_purchases_enabled do
      Subscriptions.list_plans_by_product_type(:single_purchase)
    else
      []
    end

    {:noreply,
     socket
     |> assign(:plans, plans)
     |> assign(:single_purchase_plans, single_purchase_plans)}
  end

  def handle_info({:updated, %{type: :plan}}, socket) do
    # Reload plans when a plan is updated
    subscriptions_enabled = socket.assigns.subscriptions_enabled
    single_purchases_enabled = socket.assigns.single_purchases_enabled

    # Get subscription plans only if enabled - use proper structure for plan_selector
    plans = if subscriptions_enabled do
      # Get the structured plans that plan_selector expects (with monthly/yearly per tier)
      all_plans = Subscriptions.list_all_plans()
      # Remove single_purchase key if it exists to avoid confusion
      Map.delete(all_plans, :single_purchase)
    else
      %{}
    end

    # Get single purchase products only if enabled
    single_purchase_plans = if single_purchases_enabled do
      Subscriptions.list_plans_by_product_type(:single_purchase)
    else
      []
    end

    {:noreply,
     socket
     |> assign(:plans, plans)
     |> assign(:single_purchase_plans, single_purchase_plans)}
  end

  def handle_info({:deleted, %{type: :plan}}, socket) do
    # Reload plans when a plan is deleted
    subscriptions_enabled = socket.assigns.subscriptions_enabled
    single_purchases_enabled = socket.assigns.single_purchases_enabled

    # Get subscription plans only if enabled - use proper structure for plan_selector
    plans = if subscriptions_enabled do
      # Get the structured plans that plan_selector expects (with monthly/yearly per tier)
      all_plans = Subscriptions.list_all_plans()
      # Remove single_purchase key if it exists to avoid confusion
      Map.delete(all_plans, :single_purchase)
    else
      %{}
    end

    # Get single purchase products only if enabled
    single_purchase_plans = if single_purchases_enabled do
      Subscriptions.list_plans_by_product_type(:single_purchase)
    else
      []
    end

    {:noreply,
     socket
     |> assign(:plans, plans)
     |> assign(:single_purchase_plans, single_purchase_plans)}
  end

  # Ignore other PubSub messages
  def handle_info(_msg, socket), do: {:noreply, socket}
end
