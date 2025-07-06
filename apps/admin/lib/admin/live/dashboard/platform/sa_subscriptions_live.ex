defmodule Admin.SubscriptionsLive do
  @moduledoc """
  LiveView for managing subscriptions and plans in the super admin panel.

  This view allows super admins to:
  - View all subscription plans
  - Create new plans
  - Edit existing plans
  - Delete plans
  - View active subscriptions
  - Manage subscription statuses
  - Sync with Stripe
  """
  use Admin, :live_view
  import Ecto.Query
  alias Core.Subscriptions
  alias Core.Subscriptions.{Plan, Subscription}
  alias Admin.PageMeta
  alias Core.PubSub.DataSync
  alias Admin.Components.ActivityTimelineComponent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("subscriptions", "all")
      DataSync.subscribe("plans", "all")
    end

    plans = Subscriptions.list_all_plans()
    subscriptions = list_all_subscriptions()

    {:ok,
     socket
     |> assign(:plans, plans)
     |> assign(:subscriptions, subscriptions)
     |> assign(:selected_plan_activities, [])
     |> assign(:active_tab, "monthly")
     |> assign(:current_interval, "monthly")
     |> assign(:show_plan_modal, false)
     |> assign(:show_subscription_modal, false)
     |> assign(:editing_plan, nil)
     |> assign(:editing_subscription, nil)
     |> assign(:selected_item, nil)
     |> assign(:selected_type, nil)
     |> assign(:show_drawer, false)
     |> assign(:editing_mode, false)
     |> assign(:plan_form, to_form(%{}, as: :plan))
     |> assign(:features_order, [])
     |> assign(:loading, false)
     |> PageMeta.assign_metadata(
       title: "Subscription Management",
       description: "Manage subscription plans and user subscriptions",
       url: "/dashboard/subscriptions"
     )}
  end

    @impl true
  def handle_params(params, _url, socket) do
    tab = Map.get(params, "tab", "monthly")
    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> assign(:current_interval, tab)}
  end

    @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> assign(:current_interval, tab)
     |> assign(:selected_item, nil)
     |> assign(:selected_type, nil)
     |> assign(:show_drawer, false)
     |> push_patch(to: ~p"/dashboard/subscriptions")}
  end

    @impl true
  def handle_event("select_plan", %{"id" => plan_id}, socket) do
    plan = get_plan_by_id(plan_id, socket.assigns.plans)

    if plan do
      # Load activities for this specific plan
      plan_activities = Core.Tracking.get_plan_activities(plan.id, 20)

      {:noreply,
       socket
       |> assign(:selected_item, plan)
       |> assign(:selected_type, :plan)
       |> assign(:selected_plan_activities, plan_activities)
       |> assign(:editing_mode, false)
       |> assign(:show_drawer, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_subscription", %{"id" => subscription_id}, socket) do
    subscription = Enum.find(socket.assigns.subscriptions, &(to_string(&1.id) == subscription_id))

    if subscription do
      {:noreply,
       socket
       |> assign(:selected_item, subscription)
       |> assign(:selected_type, :subscription)
       |> assign(:show_drawer, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :show_drawer, false)}
  end

  @impl true
  def handle_event("change_plan_details_tab", %{"tab" => _tab}, socket) do
    # This is handled by JavaScript in the TabsNew component
    # We just need to acknowledge the event
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_editing", _params, socket) do
    if socket.assigns.selected_item do
      plan = socket.assigns.selected_item

      # Use existing features_order from database if available, otherwise create from features
      features_order = if plan.features_order && length(plan.features_order) > 0 do
        plan.features_order
      else
        # Fallback to sorted keys if no order is defined
        Map.keys(plan.features || %{}) |> Enum.sort()
      end

      # Convert interval for form display - single purchase products have nil interval but should show "one_time"
      interval_for_form = case {plan.product_type, plan.interval} do
        {:single_purchase, nil} -> "one_time"
        {_, interval} -> interval
      end

      plan_form = to_form(%{
        "name" => plan.name,
        "description" => plan.description || "",
        "unit_amount" => to_string(plan.unit_amount),
        "currency" => plan.currency,
        "interval" => interval_for_form,
        "tier" => plan.metadata["tier"] || "",
        "features" => plan.features || %{}
      }, as: :plan)

      {:noreply,
       socket
       |> assign(:editing_mode, true)
       |> assign(:plan_form, plan_form)
       |> assign(:features_order, features_order)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_editing", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_mode, false)
     |> assign(:features_order, [])
     |> push_event("switch-tab", %{tab: "details"})}
  end

        @impl true
  def handle_event("save_inline_edit", %{"plan" => plan_params}, socket) do
    if socket.assigns.selected_item do
      plan = socket.assigns.selected_item

      # Debug: log the parameters and order
      IO.inspect(plan_params, label: "Raw plan_params")
      IO.inspect(socket.assigns.features_order, label: "Features order")

      # Process the plan parameters to handle features properly with ordering
      processed_params = process_plan_params_with_order(plan_params, socket.assigns.features_order)

      IO.inspect(processed_params, label: "Processed params")

      case Subscriptions.update_plan(plan, processed_params) do
        {:ok, updated_plan} ->
          # Calculate what actually changed
          changes = calculate_plan_changes(plan, updated_plan)

          # Only track activity if there were actual changes
          if map_size(changes) > 0 do
            Core.Tracking.track_plan_activity(
              "plan_updated",
              updated_plan,
              socket.assigns.current_user,
              changes,
              %{"updated_from" => "super_admin_interface"}
            )
          end

          # Reload all plans to get the updated data structure
          plans = Subscriptions.list_all_plans()

          # Find the updated plan in the new structure
          updated_selected_item = find_plan_in_structure(updated_plan.id, plans)

          # Reload activities for the updated plan
          plan_activities = Core.Tracking.get_plan_activities(updated_plan.id, 20)

          {:noreply,
           socket
           |> assign(:plans, plans)
           |> assign(:selected_item, updated_selected_item || updated_plan)
           |> assign(:selected_plan_activities, plan_activities)
           |> assign(:editing_mode, false)
           |> assign(:features_order, [])
           |> push_event("switch-tab", %{tab: "details"})
           |> put_flash(:info, "Plan updated successfully")}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(:plan_form, to_form(changeset, as: :plan))
           |> put_flash(:error, "Failed to update plan: #{format_changeset_errors(changeset)}")}
      end
    else
      {:noreply, socket}
    end
  end

      @impl true
  def handle_event("add_feature", _params, socket) do
    if socket.assigns.editing_mode do
      current_features = socket.assigns.plan_form.params["features"] || %{}
      current_order = socket.assigns.features_order

      # Generate a unique temporary key for new features
      temp_key = "new_feature_#{System.unique_integer([:positive])}"
      new_features = Map.put(current_features, temp_key, "")
      new_order = current_order ++ [temp_key]

      plan_params = Map.put(socket.assigns.plan_form.params, "features", new_features)
      plan_form = to_form(plan_params, as: :plan)

      {:noreply,
       socket
       |> assign(:plan_form, plan_form)
       |> assign(:features_order, new_order)}
    else
      {:noreply, socket}
    end
  end

    @impl true
  def handle_event("remove_feature", %{"key" => key}, socket) do
    if socket.assigns.editing_mode do
      current_features = socket.assigns.plan_form.params["features"] || %{}
      current_order = socket.assigns.features_order

      new_features = Map.delete(current_features, key)
      new_order = List.delete(current_order, key)

      plan_params = Map.put(socket.assigns.plan_form.params, "features", new_features)
      plan_form = to_form(plan_params, as: :plan)

      {:noreply,
       socket
       |> assign(:plan_form, plan_form)
       |> assign(:features_order, new_order)}
    else
      {:noreply, socket}
    end
  end

    @impl true
  def handle_event("validate_plan", %{"plan" => plan_params}, socket) do
    # Process features to handle dynamic key-value pairs
    processed_params = process_plan_params(plan_params)

    changeset =
      socket.assigns.selected_item
      |> Plan.changeset(processed_params)
      |> Map.put(:action, :validate)

    plan_form = to_form(changeset, as: :plan)

    {:noreply, assign(socket, :plan_form, plan_form)}
  end

  @impl true
  def handle_event("update_feature", %{"index" => index_str, "type" => type, "value" => value}, socket) do
    if socket.assigns.editing_mode do
      index = String.to_integer(index_str)
      current_features = socket.assigns.plan_form.params["features"] || %{}

      # Convert features to list to maintain order
      features_list = Enum.to_list(current_features)

      if index < length(features_list) do
        {old_key, old_value} = Enum.at(features_list, index)

        # Update the specific field
        updated_entry = case type do
          "key" -> {value, old_value}
          "value" -> {old_key, value}
        end

        # Replace at the specific index
        updated_features_list = List.replace_at(features_list, index, updated_entry)
        updated_features = Enum.into(updated_features_list, %{})

        plan_params = Map.put(socket.assigns.plan_form.params, "features", updated_features)
        plan_form = to_form(plan_params, as: :plan)

        {:noreply, assign(socket, :plan_form, plan_form)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

        @impl true
  def handle_event("reorder_features", %{"from" => from_index, "to" => to_index}, socket) do
    IO.inspect(%{from: from_index, to: to_index, editing_mode: socket.assigns.editing_mode}, label: "Reorder features event")

    if socket.assigns.editing_mode do
      features_order = socket.assigns.features_order

      IO.inspect(features_order, label: "Current features order")

      from_idx = String.to_integer(from_index)
      to_idx = String.to_integer(to_index)

      if from_idx != to_idx and from_idx < length(features_order) and to_idx < length(features_order) do
        # Move the key from from_idx to to_idx in the order list
        {key, remaining_order} = List.pop_at(features_order, from_idx)
        new_order = List.insert_at(remaining_order, to_idx, key)

        IO.inspect(new_order, label: "New features order")

        {:noreply, assign(socket, :features_order, new_order)}
      else
        IO.inspect("Invalid reorder indices", label: "Reorder error")
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("new_plan", _params, socket) do
    # Convert tab name to interval for Stripe
    interval = case socket.assigns.current_interval do
      "monthly" -> "month"
      "yearly" -> "year"
      "one_time" -> "one_time"
      _ -> "month"
    end

    plan_form = to_form(%{
      "name" => "",
      "description" => "",
      "unit_amount" => "",
      "currency" => "usd",
      "interval" => interval,
      "tier" => "",
      "features" => %{}
    }, as: :plan)

    {:noreply,
     socket
     |> assign(:show_plan_modal, true)
     |> assign(:editing_plan, nil)
     |> assign(:plan_form, plan_form)}
  end

  @impl true
  def handle_event("edit_plan", %{"id" => plan_id}, socket) do
    plan = get_plan_by_id(plan_id, socket.assigns.plans)

    if plan do
      plan_form = to_form(%{
        "name" => plan.name,
        "description" => plan.description || "",
        "unit_amount" => to_string(plan.unit_amount),
        "currency" => plan.currency,
        "interval" => plan.interval,
        "tier" => plan.metadata["tier"] || "",
        "features" => plan.features || %{}
      }, as: :plan)

      {:noreply,
       socket
       |> assign(:show_plan_modal, true)
       |> assign(:editing_plan, plan)
       |> assign(:plan_form, plan_form)}
    else
      {:noreply, put_flash(socket, :error, "Plan not found")}
    end
  end

  @impl true
  def handle_event("delete_plan", %{"id" => plan_id}, socket) do
    plan = get_plan_by_id(plan_id, socket.assigns.plans)

    if plan do
      case Subscriptions.delete_plan(plan, socket.assigns.current_user) do
        {:ok, _} ->
          plans = Subscriptions.list_all_plans()
          {:noreply,
           socket
           |> assign(:plans, plans)
           |> put_flash(:info, "Plan deleted successfully")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to delete plan")}
      end
    else
      {:noreply, put_flash(socket, :error, "Plan not found")}
    end
  end

  @impl true
  def handle_event("close_plan_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_plan_modal, false)
     |> assign(:editing_plan, nil)}
  end

  @impl true
  def handle_event("save_plan", %{"plan" => plan_params}, socket) do
    socket = assign(socket, :loading, true)

    case socket.assigns.editing_plan do
      nil ->
        # Create new plan
        normalized_params = normalize_plan_params(plan_params)
        case Subscriptions.create_plan(normalized_params, socket.assigns.current_user) do
          {:ok, _plan} ->
            plans = Subscriptions.list_all_plans()
            {:noreply,
             socket
             |> assign(:plans, plans)
             |> assign(:show_plan_modal, false)
             |> assign(:loading, false)
             |> put_flash(:info, "Plan created successfully")}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:plan_form, to_form(changeset, as: :plan))
             |> assign(:loading, false)
             |> put_flash(:error, "Failed to create plan")}
        end

      plan ->
        # Update existing plan
        normalized_params = normalize_plan_params(plan_params)
        case Subscriptions.update_plan(plan, normalized_params, socket.assigns.current_user) do
          {:ok, _plan} ->
            plans = Subscriptions.list_all_plans()
            {:noreply,
             socket
             |> assign(:plans, plans)
             |> assign(:show_plan_modal, false)
             |> assign(:loading, false)
             |> put_flash(:info, "Plan updated successfully")}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:plan_form, to_form(changeset, as: :plan))
             |> assign(:loading, false)
             |> put_flash(:error, "Failed to update plan")}
        end
    end
  end

  @impl true
  def handle_event("validate_plan", %{"plan" => plan_params}, socket) do
    changeset =
      %Plan{}
      |> Plan.changeset(normalize_plan_params(plan_params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :plan_form, to_form(changeset, as: :plan))}
  end



  @impl true
  def handle_event("update_subscription_status", %{"id" => subscription_id, "status" => status}, socket) do
    subscription = Enum.find(socket.assigns.subscriptions, &(to_string(&1.id) == subscription_id))

    if subscription do
      status_atom = String.to_atom(status)
      case Subscriptions.admin_update_subscription_status(subscription, status_atom, socket.assigns.current_user) do
        {:ok, _updated_subscription} ->
          subscriptions = list_all_subscriptions()
          {:noreply,
           socket
           |> assign(:subscriptions, subscriptions)
           |> put_flash(:info, "Subscription status updated successfully")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to update subscription status")}
      end
    else
      {:noreply, put_flash(socket, :error, "Subscription not found")}
    end
  end

    @impl true
  def handle_info({:created, %{type: :plan}}, socket) do
    plans = Subscriptions.list_all_plans()
    {:noreply, assign(socket, :plans, plans)}
  end

  def handle_info({:updated, %{type: :plan}}, socket) do
    plans = Subscriptions.list_all_plans()

    # If we have a selected plan, refresh its activities
    updated_socket = if socket.assigns.selected_item && socket.assigns.selected_type == :plan do
      plan_activities = Core.Tracking.get_plan_activities(socket.assigns.selected_item.id, 20)
      assign(socket, :selected_plan_activities, plan_activities)
    else
      socket
    end

    {:noreply, assign(updated_socket, :plans, plans)}
  end

  def handle_info({:deleted, %{type: :plan}}, socket) do
    plans = Subscriptions.list_all_plans()
    {:noreply,
     socket
     |> assign(:plans, plans)
     |> assign(:selected_item, nil)
     |> assign(:selected_type, nil)
     |> assign(:selected_plan_activities, [])
     |> assign(:show_drawer, false)}
  end

  # Ignore other PubSub messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # Helper functions

  defp list_all_subscriptions do
    Core.Repo.all(
      from s in Subscription,
      join: u in assoc(s, :user),
      join: p in assoc(s, :plan),
      preload: [user: u, plan: p],
      order_by: [desc: s.inserted_at]
    )
  end

  defp get_plan_by_id(plan_id, plans) do
    plan_id = String.to_integer(plan_id)

    # First check single purchase products
    single_purchase_plans = Map.get(plans, :single_purchase, [])
    single_purchase_match = Enum.find(single_purchase_plans, &(&1.id == plan_id))

    if single_purchase_match do
      single_purchase_match
    else
      # Then check subscription plans
      Enum.find_value(plans, fn {tier, tier_plans} ->
        if tier == :single_purchase do
          nil
        else
          Enum.find([tier_plans.monthly, tier_plans.yearly], &(&1 && &1.id == plan_id))
        end
      end)
    end
  end

  defp normalize_plan_params(params) do
    # Determine product type based on interval
    product_type = if params["interval"] == "one_time", do: :single_purchase, else: :subscription

    # Set interval to nil for single purchase products
    interval = if product_type == :single_purchase, do: nil, else: params["interval"]

    %{
      name: params["name"],
      description: params["description"],
      unit_amount: String.to_integer(params["unit_amount"]),
      currency: params["currency"],
      interval: interval,
      product_type: product_type,
      metadata: %{"tier" => params["tier"]},
      features: parse_features(params["features"] || %{}),
      features_order: params["features_order"] || []
    }
  end

  defp parse_features(features) when is_map(features), do: features
  defp parse_features(_), do: %{}



  defp format_currency(amount) when is_integer(amount) do
    "$#{Float.round(amount / 100, 2)}"
  end

  defp format_currency(_), do: "$0.00"

  # defp format_features(features) when is_map(features) do
  #   features
  #   |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
  #   |> Enum.join(", ")
  # end

  # defp format_features(_), do: "None"

  # Helper function to get plans by interval
  defp get_plans_by_interval(plans, interval) do
    case interval do
      "one_time" ->
        # Return single purchase products
        Map.get(plans, :single_purchase, [])
      _ ->
        # Handle subscription plans - collect ALL plans matching the interval
        # regardless of tier structure to ensure no plans are lost
        target_interval = case interval do
          "monthly" -> "month"
          "yearly" -> "year"
          "month" -> "month"
          "year" -> "year"
          _ -> interval
        end

        # Flatten all subscription plans and filter by interval
        all_subscription_plans = plans
        |> Enum.flat_map(fn {tier, tier_plans} ->
          # Skip the :single_purchase key since it's not a tier
          if tier == :single_purchase do
            []
          else
            # Collect all non-nil plans from this tier
            case tier_plans do
              %{monthly: monthly, yearly: yearly} ->
                [monthly, yearly] |> Enum.filter(& &1)
              _ ->
                []
            end
          end
        end)
        |> Enum.filter(&(&1.interval == target_interval)) # Filter by actual interval
        |> Enum.sort_by(& &1.unit_amount) # Sort by unit_amount to maintain consistent ordering

        all_subscription_plans
    end
  end

    # Details rendering function
  defp render_details(assigns) do
    context = assigns[:context] || "desktop"
    assigns = assign(assigns, :context, context)

    ~H"""
    <%= if @selected_type == :plan do %>
      <%= if @editing_mode do %>
        <div class="space-y-4 p-2">
          <.form
            for={@plan_form}
            phx-change="validate_plan"
            phx-submit="save_inline_edit"
            class="space-y-4"
          >
            <div class="grid grid-cols-1 gap-4">
              <div>
                <label class="label" for="plan_name">
                  <span class="label-text">Name</span>
                </label>
                <input
                  type="text"
                  id="plan_name"
                  name="plan[name]"
                  class="input input-bordered w-full"
                  value={Phoenix.HTML.Form.input_value(@plan_form, :name)}
                  placeholder="Enter plan name"
                  required
                />
              </div>

              <div>
                <label class="label" for="plan_description">
                  <span class="label-text">Description</span>
                </label>
                <textarea
                  id="plan_description"
                  name="plan[description]"
                  class="textarea textarea-bordered w-full"
                  placeholder="Enter plan description"
                ><%= Phoenix.HTML.Form.input_value(@plan_form, :description) %></textarea>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="label" for="plan_unit_amount">
                    <span class="label-text">Price (cents)</span>
                  </label>
                  <input
                    type="number"
                    id="plan_unit_amount"
                    name="plan[unit_amount]"
                    class="input input-bordered w-full"
                    value={Phoenix.HTML.Form.input_value(@plan_form, :unit_amount)}
                    placeholder="Enter price in cents"
                    required
                  />
                </div>

                <div>
                  <label class="label" for={"plan-tier-select-#{@context}"}>
                    <span class="label-text">Tier *</span>
                  </label>
                  <select
                    id={"plan-tier-select-#{@context}"}
                    name="plan[tier]"
                    class="select select-bordered w-full"
                  >
                    <option value="small" selected={@plan_form.params["tier"] == "small"}>
                      Small
                    </option>
                    <option value="medium" selected={@plan_form.params["tier"] == "medium"}>
                      Medium
                    </option>
                    <option value="large" selected={@plan_form.params["tier"] == "large"}>
                      Large
                    </option>
                  </select>
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="label" for={"plan-currency-select-#{@context}"}>
                    <span class="label-text">Currency *</span>
                  </label>
                  <select
                    id={"plan-currency-select-#{@context}"}
                    name="plan[currency]"
                    class="select select-bordered w-full"
                  >
                    <option value="usd" selected={@plan_form.params["currency"] == "usd"}>USD</option>
                  </select>
                </div>

                <div>
                  <label class="label" for={"plan-interval-select-#{@context}"}>
                    <span class="label-text">Billing Type *</span>
                  </label>
                  <select
                    id={"plan-interval-select-#{@context}"}
                    name="plan[interval]"
                    class="select select-bordered w-full"
                  >
                    <option value="month" selected={@plan_form.params["interval"] == "month"}>
                      Monthly
                    </option>
                    <option value="year" selected={@plan_form.params["interval"] == "year"}>
                      Yearly
                    </option>
                    <option value="one_time" selected={@plan_form.params["interval"] == "one_time"}>
                      One-time
                    </option>
                  </select>
                </div>
              </div>

              <div>
                <div class="flex justify-between items-center mb-2">
                  <label class="label">
                    <span class="label-text">Features</span>
                  </label>
                  <button
                    type="button"
                    class="btn btn-sm btn-outline"
                    phx-click="add_feature"
                  >
                    <.icon name="hero-plus" class="h-3 w-3 mr-1" />
                    Add Feature
                  </button>
                </div>

                <%= if @plan_form.params["features"] && map_size(@plan_form.params["features"]) > 0 do %>
                  <div
                    class="space-y-2"
                    id="features-container"
                    phx-hook="Sortable"
                    data-group="features"
                  >
                    <%= for {key, index} <- Enum.with_index(@features_order) do %>
                      <% value = @plan_form.params["features"][key] || "" %>
                      <div
                        class="flex gap-2 items-center bg-base-200 p-2 rounded border"
                        id={"feature-#{index}"}
                        data-feature-key={key}
                        data-feature-value={value}
                        data-index={index}
                      >
                        <div class="drag-handle cursor-move text-base-content/40 hover:text-base-content/60 flex-shrink-0">
                          <.icon name="hero-bars-3" class="h-4 w-4" />
                        </div>

                        <input
                          type="hidden"
                          name={"plan[features_to_remove][]"}
                          value={key}
                          disabled
                        />
                        <input
                          type="text"
                          name={"plan[feature_keys][]"}
                          value={key}
                          placeholder="Feature name"
                          class="input input-bordered input-sm flex-1"
                          phx-debounce="300"
                          phx-blur="update_feature"
                          phx-value-index={index}
                          phx-value-type="key"
                        />
                        <input
                          type="text"
                          name={"plan[feature_values][]"}
                          value={value}
                          placeholder="Feature value"
                          class="input input-bordered input-sm flex-1"
                          phx-debounce="300"
                          phx-blur="update_feature"
                          phx-value-index={index}
                          phx-value-type="value"
                        />
                        <button
                          type="button"
                          class="btn btn-sm btn-ghost"
                          phx-click="remove_feature"
                          phx-value-key={key}
                        >
                          <.icon name="hero-x-mark" class="h-3 w-3" />
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="text-sm text-base-content/70 italic">No features added yet</p>
                <% end %>
              </div>
            </div>

            <div class="border-t pt-4">
              <div class="flex gap-2">
                <button
                  type="submit"
                  class="btn btn-primary flex-1"
                >
                  <.icon name="hero-check" class="h-3 w-3 mr-1" />
                  Save Changes
                </button>
                <button
                  type="button"
                  class="btn btn-outline flex-1"
                  phx-click="cancel_editing"
                >
                  <.icon name="hero-x-mark" class="h-3 w-3 mr-1" />
                  Cancel
                </button>
              </div>
            </div>
          </.form>
        </div>
      <% else %>
        <div role="tablist" class="tabs tabs-lifted">
          <input
            type="radio"
            name={"plan_tabs_#{@context}"}
            role="tab"
            class="tab"
            aria-label="Details"
            checked
          />
          <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
            <div class="grid grid-cols-1 gap-4 mt-2 p-2">
              <div>
                <h4 class="text-sm font-medium text-base-content/70">Name</h4>
                <p class="mt-1 text-lg font-semibold">{@selected_item.name}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Description</h4>
                <p class="mt-1">{@selected_item.description || "No description"}</p>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <h4 class="text-sm font-medium text-base-content/70">Price</h4>
                  <p class="mt-1 text-2xl font-bold text-base-content">
                    {format_currency(@selected_item.unit_amount)}
                  </p>
                  <p class="text-sm text-base-content/70">
                    <%= if @selected_item.interval == "one_time" do %>
                      one-time purchase
                    <% else %>
                      per {@selected_item.interval}
                    <% end %>
                  </p>
                </div>

                <div>
                  <h4 class="text-sm font-medium text-base-content/70">Tier</h4>
                  <p class="mt-1 capitalize">{@selected_item.metadata["tier"] || "None"}</p>
                </div>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Currency</h4>
                <p class="mt-1 uppercase">{@selected_item.currency}</p>
              </div>

              <%= if @selected_item.features && map_size(@selected_item.features) > 0 do %>
                <div>
                  <h4 class="text-sm font-medium text-base-content/70">Features</h4>
                  <div class="mt-1 space-y-1">
                    <%= for key <- get_ordered_feature_keys(@selected_item) do %>
                      <% value = Map.get(@selected_item.features, key, "") %>
                      <div class="flex justify-between py-1 border-b border-base-300">
                        <span class="text-sm text-base-content/80 capitalize">{key}:</span>
                        <span class="text-sm font-medium">{value}</span>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <div>
                  <h4 class="text-sm font-medium text-base-content/70">Features</h4>
                  <p class="mt-1 text-sm text-base-content/70 italic">No features defined</p>
                </div>
              <% end %>

              <div class="border-t pt-4">
                <h4 class="text-sm font-medium text-base-content/70">Stripe Information</h4>
                <div class="mt-2 space-y-2">
                  <div>
                    <span class="text-xs text-base-content/70">Product ID:</span>
                    <p class="text-xs font-mono bg-base-200 p-1 rounded">{@selected_item.stripe_product_id}</p>
                  </div>
                  <div>
                    <span class="text-xs text-base-content/70">Price ID:</span>
                    <p class="text-xs font-mono bg-base-200 p-1 rounded">{@selected_item.stripe_price_id}</p>
                  </div>
                </div>
              </div>

              <div class="border-t pt-4">
                <h4 class="text-sm font-medium text-base-content/70">Timestamps</h4>
                <div class="flex justify-between items-center mt-2 text-xs text-base-content/70">
                  <p>Created: {Calendar.strftime(@selected_item.inserted_at, "%B %d, %Y at %H:%M")}</p>
                  <p>Updated: {Calendar.strftime(@selected_item.updated_at, "%B %d, %Y at %H:%M")}</p>
                </div>
              </div>

              <div class="flex justify-center items-center w-full">
                <button
                  class="btn btn-error btn-sm w-full"
                  phx-click="delete_plan"
                  phx-value-id={@selected_item.id}
                  data-confirm="Are you sure you want to delete this plan?"
                >
                  <.icon name="hero-trash" class="h-3 w-3 mr-1" />
                  Delete Plan
                </button>
              </div>
            </div>
          </div>

          <input
            type="radio"
            name={"plan_tabs_#{@context}"}
            role="tab"
            class="tab"
            aria-label="Edit"
          />
          <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
            <div class="mt-2 relative p-2">
              <%= if @editing_mode do %>
                <div class="space-y-4">
                  <.form
                    for={@plan_form}
                    phx-change="validate_plan"
                    phx-submit="save_inline_edit"
                    class="space-y-4"
                  >
                    <div class="grid grid-cols-1 gap-4">
                      <div>
                        <label class="label" for={"plan_name_#{@context}"}>
                          <span class="label-text">Name</span>
                        </label>
                        <input
                          type="text"
                          id={"plan_name_#{@context}"}
                          name="plan[name]"
                          value={@plan_form.params["name"]}
                          class="input input-bordered w-full"
                          required
                        />
                      </div>

                      <div>
                        <label class="label" for={"plan_description_#{@context}"}>
                          <span class="label-text">Description</span>
                        </label>
                        <textarea
                          id={"plan_description_#{@context}"}
                          name="plan[description]"
                          class="textarea textarea-bordered w-full"
                        ><%= @plan_form.params["description"] %></textarea>
                      </div>

                      <div class="grid grid-cols-2 gap-4">
                        <div>
                          <label class="label" for={"plan_unit_amount_#{@context}"}>
                            <span class="label-text">Price (cents)</span>
                          </label>
                          <input
                            type="number"
                            id={"plan_unit_amount_#{@context}"}
                            name="plan[unit_amount]"
                            value={@plan_form.params["unit_amount"]}
                            class="input input-bordered w-full"
                            required
                          />
                        </div>

                        <div>
                          <label class="label" for={"plan-tier-select-edit-#{@context}"}>
                            <span class="label-text">Tier *</span>
                          </label>
                          <select
                            id={"plan-tier-select-edit-#{@context}"}
                            name="plan[tier]"
                            class="select select-bordered w-full"
                          >
                            <option
                              value="small"
                              selected={@plan_form.params["tier"] == "small"}
                            >
                              Small
                            </option>
                            <option
                              value="medium"
                              selected={@plan_form.params["tier"] == "medium"}
                            >
                              Medium
                            </option>
                            <option
                              value="large"
                              selected={@plan_form.params["tier"] == "large"}
                            >
                              Large
                            </option>
                          </select>
                        </div>
                      </div>

                      <div class="grid grid-cols-2 gap-4">
                        <div>
                          <label class="label" for={"plan-currency-select-edit-#{@context}"}>
                            <span class="label-text">Currency *</span>
                          </label>
                          <select
                            id={"plan-currency-select-edit-#{@context}"}
                            name="plan[currency]"
                            class="select select-bordered w-full"
                          >
                            <option value="usd" selected={@plan_form.params["currency"] == "usd"}>
                              USD
                            </option>
                          </select>
                        </div>

                        <div>
                          <label class="label" for={"plan-interval-select-edit-#{@context}"}>
                            <span class="label-text">Billing Type *</span>
                          </label>
                          <select
                            id={"plan-interval-select-edit-#{@context}"}
                            name="plan[interval]"
                            class="select select-bordered w-full"
                          >
                            <option
                              value="month"
                              selected={@plan_form.params["interval"] == "month"}
                            >
                              Monthly
                            </option>
                            <option
                              value="year"
                              selected={@plan_form.params["interval"] == "year"}
                            >
                              Yearly
                            </option>
                            <option
                              value="one_time"
                              selected={@plan_form.params["interval"] == "one_time"}
                            >
                              One-time
                            </option>
                          </select>
                        </div>
                      </div>

                      <div>
                        <div class="flex justify-between items-center mb-2">
                          <label class="text-sm font-medium text-base-content/70">Features</label>
                          <button
                            type="button"
                            class="btn btn-outline btn-sm"
                            phx-click="add_feature"
                          >
                            <.icon name="hero-plus" class="h-3 w-3 mr-1" />
                            Add Feature
                          </button>
                        </div>

                        <%= if @plan_form.params["features"] && map_size(@plan_form.params["features"]) > 0 do %>
                          <div
                            class="space-y-2"
                            id={"features-container-#{@context}"}
                            phx-hook="Sortable"
                            data-group="features"
                          >
                            <%= for {key, index} <- Enum.with_index(@features_order) do %>
                              <% value = @plan_form.params["features"][key] || "" %>
                              <div
                                class="flex gap-2 items-center bg-base-200 p-2 rounded border"
                                id={"feature-#{index}-#{@context}"}
                                data-feature-key={key}
                                data-feature-value={value}
                                data-index={index}
                              >
                                <div class="drag-handle cursor-move text-base-content/40 hover:text-base-content/60 flex-shrink-0">
                                  <.icon name="hero-bars-3" class="h-4 w-4" />
                                </div>

                                <input
                                  type="hidden"
                                  name={"plan[features_to_remove][]"}
                                  value={key}
                                  disabled
                                />
                                <input
                                  type="text"
                                  name={"plan[feature_keys][]"}
                                  value={key}
                                  placeholder="Feature name"
                                  class="input input-bordered input-sm flex-1"
                                  phx-debounce="300"
                                  phx-blur="update_feature"
                                  phx-value-index={index}
                                  phx-value-type="key"
                                />
                                <input
                                  type="text"
                                  name={"plan[feature_values][]"}
                                  value={value}
                                  placeholder="Feature value"
                                  class="input input-bordered input-sm flex-1"
                                  phx-debounce="300"
                                  phx-blur="update_feature"
                                  phx-value-index={index}
                                  phx-value-type="value"
                                />
                                <button
                                  type="button"
                                  class="btn btn-outline btn-sm"
                                  phx-click="remove_feature"
                                  phx-value-key={key}
                                >
                                  <.icon name="hero-x-mark" class="h-3 w-3" />
                                </button>
                              </div>
                            <% end %>
                          </div>
                        <% else %>
                          <p class="text-sm text-base-content/70 italic">No features added yet</p>
                        <% end %>
                      </div>
                    </div>

                    <div class="border-t pt-4">
                      <div class="flex gap-2">
                        <button
                          type="submit"
                          class="btn btn-primary flex-1"
                        >
                          <.icon name="hero-check" class="h-3 w-3 mr-1" />
                          Save Changes
                        </button>
                        <button
                          type="button"
                          class="btn btn-outline flex-1"
                          phx-click="cancel_editing"
                        >
                          <.icon name="hero-x-mark" class="h-3 w-3 mr-1" />
                          Cancel
                        </button>
                      </div>
                    </div>
                  </.form>
                </div>
              <% else %>
                <!-- Edit Overlay -->
                <div class="relative">
                  <!-- Background content (read-only view) -->
                  <div class="opacity-50 pointer-events-none">
                    <div class="grid grid-cols-1 gap-4">
                      <div>
                        <h4 class="text-sm font-medium text-base-content/70">Name</h4>
                        <p class="mt-1 text-lg font-semibold">{@selected_item.name}</p>
                      </div>

                      <div>
                        <h4 class="text-sm font-medium text-base-content/70">Description</h4>
                        <p class="mt-1">{@selected_item.description || "No description"}</p>
                      </div>

                      <div class="grid grid-cols-2 gap-4">
                        <div>
                          <h4 class="text-sm font-medium text-base-content/70">Price</h4>
                          <p class="mt-1 text-2xl font-bold text-base-content">
                            {format_currency(@selected_item.unit_amount)}
                          </p>
                        </div>

                        <div>
                          <h4 class="text-sm font-medium text-base-content/70">Tier</h4>
                          <p class="mt-1 capitalize">
                            {@selected_item.metadata["tier"] || "No"}
                          </p>
                        </div>
                      </div>

                      <%= if @selected_item.features && map_size(@selected_item.features) > 0 do %>
                        <div>
                          <h4 class="text-sm font-medium text-base-content/70">Features</h4>
                          <div class="mt-1 space-y-1">
                            <%= for key <- get_ordered_feature_keys(@selected_item) do %>
                              <% value = Map.get(@selected_item.features, key, "") %>
                              <div class="flex justify-between py-1 border-b border-base-200">
                                <span class="text-sm text-base-content/80 capitalize">
                                  {key}:
                                </span>
                                <span class="text-sm font-medium">{value}</span>
                              </div>
                            <% end %>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <!-- Centered Edit Button Overlay -->
                  <div class="absolute inset-0 flex items-center justify-center">
                    <div class="bg-base-100/90 backdrop-blur-sm rounded-lg border-2 border-dashed border-base-300 p-8 text-center shadow-lg">
                      <.icon name="hero-pencil-square" class="h-12 w-12 mx-auto text-base-content/40 mb-4" />
                      <h3 class="text-lg font-medium text-base-content mb-2">Edit Plan</h3>
                      <p class="text-sm text-base-content/70 mb-4">
                        Click to unlock editing mode and modify plan details
                      </p>
                      <button
                        class="btn btn-primary w-full"
                        phx-click="start_editing"
                      >
                        <.icon name="hero-pencil" class="h-4 w-4 mr-2" />
                        Start Editing
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <input
            type="radio"
            name={"plan_tabs_#{@context}"}
            role="tab"
            class="tab"
            aria-label="Timeline"
          />
          <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
            <div class="mt-4">
              <%= if length(@selected_plan_activities) > 0 do %>
                <div class="space-y-4">
                  <div class="text-sm text-base-content/70">
                    <p>
                      Track changes made to this plan including creation, updates, and modifications.
                    </p>
                  </div>
                  <.live_component
                    module={ActivityTimelineComponent}
                    id={"sa-subscriptions-plan-timeline-#{@selected_item.id}-#{@context}"}
                    activities={@selected_plan_activities}
                    user_id={@current_user.id}
                    show_timestamps={true}
                  />
                </div>
              <% else %>
                <div class="text-center py-8">
                  <.icon name="hero-clock" class="h-8 w-8 mx-auto text-base-content/40 mb-2" />
                  <h4 class="text-sm font-medium text-base-content mb-1">No activity yet</h4>
                  <p class="text-xs text-base-content/70">
                    Changes to this plan will appear here.
                  </p>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    <% else %>
      <p class="text-base-content/70">No details available</p>
    <% end %>
    """
  end

  # Plans by interval component
  defp plans_by_interval_tab(assigns) do
    interval_plans = get_plans_by_interval(assigns.plans, assigns.interval)
    assigns = assign(assigns, :interval_plans, interval_plans)

    ~H"""
    <div class="space-y-6">
      <%= if Enum.empty?(@interval_plans) do %>
        <div class="text-center py-12">
          <.icon name="hero-credit-card" class="h-12 w-12 mx-auto text-base-content/40 mb-4" />
          <h3 class="text-lg font-medium text-base-content mb-2">
            <%= if @interval == "one_time" do %>
              No single purchase products found
            <% else %>
              No {@interval} plans found
            <% end %>
          </h3>
          <p class="text-base-content/70 mb-4">
            <%= if @interval == "one_time" do %>
              Get started by creating your first single purchase product.
            <% else %>
              Get started by creating your first {@interval} subscription plan.
            <% end %>
          </p>
        </div>
      <% else %>
        <div class="flex flex-col gap-4">
          <%= for plan <- @interval_plans do %>
            <div
              class={[
                "border border-base-300 rounded-lg p-6 cursor-pointer hover:bg-base-200 transition-colors",
                (if @selected_item && @selected_type == :plan && @selected_item.id == plan.id,
                  do: "bg-base-200 border-l-4 border-primary",
                  else: "")
              ]}
              phx-click="select_plan"
              phx-value-id={plan.id}
            >
              <div class="flex justify-between items-center mb-4">
                <h4 class="text-lg font-semibold text-base-content">{plan.name}</h4>
                <p class="text-sm text-base-content/70 capitalize">
                  {plan.metadata["tier"] || "No"} Tier
                </p>
              </div>

              <div class="space-y-3">
                <div>
                  <p class="text-3xl font-bold text-base-content">
                    {format_currency(plan.unit_amount)}
                  </p>
                  <p class="text-sm text-base-content/70">
                    <%= if @interval == "one_time" do %>
                      one-time purchase
                    <% else %>
                      per {plan.interval}
                    <% end %>
                  </p>
                </div>

                <%= if plan.description do %>
                  <p class="text-sm text-base-content/80">{plan.description}</p>
                <% end %>

                <div class="flex justify-between items-center border-t pt-3">
                  <p class="text-xs text-base-content/50">Stripe ID: {plan.stripe_price_id}</p>
                  <p class="text-xs text-base-content/50">{String.upcase(plan.currency)}</p>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        Subscription Management
        <:subtitle>Manage subscription plans</:subtitle>
        <:actions>
          <div class="flex gap-2">
            <button class="btn btn-primary" phx-click="new_plan">
              <.icon name="hero-plus" class="h-4 w-4 mr-2" />
              New <%= if @current_interval == "one_time", do: "Single Purchase", else: "#{String.capitalize(@current_interval)} Plan" %>
            </button>
          </div>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mt-4 h-[calc(100vh-200px)]">
        <div class="h-[calc(100vh-200px)] col-span-1">
          <div role="tablist" class="tabs tabs-lifted">
            <input
              type="radio"
              name="subscription_tabs"
              role="tab"
              class="tab"
              aria-label="Monthly"
              checked={@active_tab == "monthly"}
              phx-click="change_tab"
              phx-value-tab="monthly"
            />
            <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
              <.plans_by_interval_tab
                plans={@plans}
                interval="monthly"
                loading={@loading}
                selected_item={@selected_item}
                selected_type={@selected_type}
              />
            </div>

            <input
              type="radio"
              name="subscription_tabs"
              role="tab"
              class="tab"
              aria-label="Yearly"
              checked={@active_tab == "yearly"}
              phx-click="change_tab"
              phx-value-tab="yearly"
            />
            <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
              <.plans_by_interval_tab
                plans={@plans}
                interval="yearly"
                loading={@loading}
                selected_item={@selected_item}
                selected_type={@selected_type}
              />
            </div>

            <input
              type="radio"
              name="subscription_tabs"
              role="tab"
              class="tab"
              aria-label="One-time"
              checked={@active_tab == "one_time"}
              phx-click="change_tab"
              phx-value-tab="one_time"
            />
            <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
              <.plans_by_interval_tab
                plans={@plans}
                interval="one_time"
                loading={@loading}
                selected_item={@selected_item}
                selected_type={@selected_type}
              />
            </div>
          </div>
        </div>

        <div class="hidden lg:block col-span-1">
          <h2 class="text-xl font-semibold mb-4">Details</h2>
          <%= if @selected_item do %>
            <.render_details
              selected_item={@selected_item}
              selected_type={@selected_type}
              editing_mode={@editing_mode}
              plan_form={@plan_form}
              features_order={@features_order}
              selected_plan_activities={@selected_plan_activities}
              current_user={@current_user}
              context="desktop"
            />
          <% else %>
            <p class="text-base-content/70">Select an item to view details</p>
          <% end %>
        </div>
      </div>

      <dialog class={["modal", (@show_drawer and @selected_item != nil) && "modal-open"]}>
        <div class="modal-box w-11/12 max-w-5xl">
          <h3 class="font-bold text-lg">
            <%= case @selected_type do %>
              <% :plan -> %>Plan Details
              <% _ -> %>Details
            <% end %>
          </h3>
          <%= if @selected_item do %>
            <p class="py-4">
              <%= case @selected_type do %>
                <% :plan -> %>{@selected_item.name}
                <% _ -> %>
              <% end %>
            </p>
          <% end %>
          <%= if @selected_item do %>
            <.render_details
              selected_item={@selected_item}
              selected_type={@selected_type}
              editing_mode={@editing_mode}
              plan_form={@plan_form}
              features_order={@features_order}
              selected_plan_activities={@selected_plan_activities}
              current_user={@current_user}
              context="mobile"
            />
          <% end %>
        </div>
        <form method="dialog" class="modal-backdrop" phx-click="close_drawer">
          <button>close</button>
        </form>
      </dialog>

      <%!-- <.plan_modal
        show={@show_plan_modal}
        form={@plan_form}
        editing_plan={@editing_plan}
        loading={@loading}
      /> --%>
    </div>
    """
  end

    # Helper function to process plan parameters from the form
  defp process_plan_params(params) do
    # Handle features if they exist
    processed_params = if params["feature_keys"] && params["feature_values"] do
      feature_keys = params["feature_keys"] || []
      feature_values = params["feature_values"] || []

      # Combine keys and values into a features map, filtering out empty ones
      features =
        Enum.zip(feature_keys, feature_values)
        |> Enum.reject(fn {key, value} -> key == "" or value == "" end)
        |> Enum.into(%{})

      params
      |> Map.put("features", features)
      |> Map.delete("feature_keys")
      |> Map.delete("feature_values")
      |> Map.delete("features_to_remove")
    else
      params
    end

    # Convert unit_amount to integer if it's a string
    if processed_params["unit_amount"] && is_binary(processed_params["unit_amount"]) do
      case Integer.parse(processed_params["unit_amount"]) do
        {amount, ""} -> Map.put(processed_params, "unit_amount", amount)
        _ -> processed_params
      end
    else
      processed_params
    end
  end

      # Helper function to process plan parameters with feature ordering
  defp process_plan_params_with_order(params, features_order) do
    # Handle features from feature_keys and feature_values arrays (from form submission)
    processed_params = if params["feature_keys"] && params["feature_values"] do
      feature_keys = params["feature_keys"] || []
      feature_values = params["feature_values"] || []

      # If we have a features_order, use it to determine the correct order
      # Otherwise, use the order from the form arrays
      features = if length(features_order) > 0 do
        # Create a map from the form data first
        form_features =
          Enum.zip(feature_keys, feature_values)
          |> Enum.reject(fn {key, value} -> key == "" or value == "" end)
          |> Enum.into(%{})

        # Now reconstruct in the correct order using features_order
        features_order
        |> Enum.filter(&Map.has_key?(form_features, &1))  # Only include keys that still exist
        |> Enum.map(&{&1, form_features[&1]})
        |> Enum.into(%{})
      else
        # Fallback to form order if no features_order
        Enum.zip(feature_keys, feature_values)
        |> Enum.reject(fn {key, value} -> key == "" or value == "" end)
        |> Enum.into(%{})
      end

      params
      |> Map.put("features", features)
      |> Map.put("features_order", features_order)
      |> Map.delete("feature_keys")
      |> Map.delete("feature_values")
      |> Map.delete("features_to_remove")
    else
      # Fallback for when we have features directly and need to apply ordering
      if params["features"] && length(features_order) > 0 do
        current_features = params["features"]

        # Reconstruct features map in the specified order
        ordered_features =
          features_order
          |> Enum.filter(&Map.has_key?(current_features, &1))  # Only include keys that still exist
          |> Enum.map(&{&1, current_features[&1]})
          |> Enum.into(%{})

        params
        |> Map.put("features", ordered_features)
        |> Map.put("features_order", features_order)
      else
        params
      end
    end

    # Convert unit_amount to integer if it's a string
    processed_params = if processed_params["unit_amount"] && is_binary(processed_params["unit_amount"]) do
      case Integer.parse(processed_params["unit_amount"]) do
        {amount, ""} -> Map.put(processed_params, "unit_amount", amount)
        _ -> processed_params
      end
    else
      processed_params
    end

    # Handle interval conversion for single purchase products
    processed_params = if processed_params["interval"] == "one_time" do
      processed_params
      |> Map.put("interval", nil)
      |> Map.put("product_type", :single_purchase)
    else
      Map.put(processed_params, "product_type", :subscription)
    end

    processed_params
  end

  # Helper function to find a plan in the structured plans data
  defp find_plan_in_structure(plan_id, plans) do
    # First check single purchase products
    single_purchase_plans = Map.get(plans, :single_purchase, [])
    single_purchase_match = Enum.find(single_purchase_plans, &(&1.id == plan_id))

    if single_purchase_match do
      single_purchase_match
    else
      # Then check subscription plans
      plans
      |> Enum.flat_map(fn {tier, tier_plans} ->
        if tier == :single_purchase do
          []
        else
          [tier_plans.monthly, tier_plans.yearly]
          |> Enum.filter(& &1)
        end
      end)
      |> Enum.find(&(&1.id == plan_id))
    end
  end

  # Helper function to get ordered feature keys for display
  defp get_ordered_feature_keys(plan) do
    if plan.features_order && length(plan.features_order) > 0 do
      # Use the saved order from database
      plan.features_order
      |> Enum.filter(&Map.has_key?(plan.features || %{}, &1))  # Only include keys that exist in features
    else
      # Fallback to sorted keys if no order is defined
      Map.keys(plan.features || %{}) |> Enum.sort()
    end
  end

  # Helper function to calculate what changed between two plans
  defp calculate_plan_changes(old_plan, new_plan) do
    changes = %{}

    # Check each field for changes
    changes = if old_plan.name != new_plan.name do
      Map.put(changes, "name", %{"from" => old_plan.name, "to" => new_plan.name})
    else
      changes
    end

    changes = if old_plan.description != new_plan.description do
      Map.put(changes, "description", %{"from" => old_plan.description, "to" => new_plan.description})
    else
      changes
    end

    changes = if old_plan.unit_amount != new_plan.unit_amount do
      Map.put(changes, "unit_amount", %{
        "from" => old_plan.unit_amount,
        "to" => new_plan.unit_amount,
        "from_formatted" => "$#{Float.round(old_plan.unit_amount / 100, 2)}",
        "to_formatted" => "$#{Float.round(new_plan.unit_amount / 100, 2)}"
      })
    else
      changes
    end

    changes = if old_plan.currency != new_plan.currency do
      Map.put(changes, "currency", %{"from" => old_plan.currency, "to" => new_plan.currency})
    else
      changes
    end

    changes = if old_plan.interval != new_plan.interval do
      Map.put(changes, "interval", %{
        "from" => old_plan.interval || "one_time",
        "to" => new_plan.interval || "one_time"
      })
    else
      changes
    end

    changes = if old_plan.product_type != new_plan.product_type do
      Map.put(changes, "product_type", %{"from" => old_plan.product_type, "to" => new_plan.product_type})
    else
      changes
    end

    # Check metadata changes (tier)
    old_tier = get_in(old_plan.metadata, ["tier"])
    new_tier = get_in(new_plan.metadata, ["tier"])
    changes = if old_tier != new_tier do
      Map.put(changes, "tier", %{"from" => old_tier, "to" => new_tier})
    else
      changes
    end

    # Check features changes
    changes = if old_plan.features != new_plan.features do
      features_changes = calculate_features_changes(old_plan.features || %{}, new_plan.features || %{})
      if map_size(features_changes) > 0 do
        Map.put(changes, "features", features_changes)
      else
        changes
      end
    else
      changes
    end

    # Check features_order changes
    changes = if old_plan.features_order != new_plan.features_order do
      Map.put(changes, "features_order", %{
        "from" => old_plan.features_order || [],
        "to" => new_plan.features_order || []
      })
    else
      changes
    end

    changes
  end

  # Helper function to calculate features changes
  defp calculate_features_changes(old_features, new_features) do
    old_keys = MapSet.new(Map.keys(old_features))
    new_keys = MapSet.new(Map.keys(new_features))

    added = MapSet.difference(new_keys, old_keys) |> MapSet.to_list()
    removed = MapSet.difference(old_keys, new_keys) |> MapSet.to_list()
    common = MapSet.intersection(old_keys, new_keys) |> MapSet.to_list()

    # Check for modified features
    modified = Enum.filter(common, fn key ->
      old_features[key] != new_features[key]
    end)

    changes = %{}

    changes = if length(added) > 0 do
      added_features = Enum.into(added, %{}, fn key -> {key, new_features[key]} end)
      Map.put(changes, "added", added_features)
    else
      changes
    end

    changes = if length(removed) > 0 do
      removed_features = Enum.into(removed, %{}, fn key -> {key, old_features[key]} end)
      Map.put(changes, "removed", removed_features)
    else
      changes
    end

    changes = if length(modified) > 0 do
      modified_features = Enum.into(modified, %{}, fn key ->
        {key, %{"from" => old_features[key], "to" => new_features[key]}}
      end)
      Map.put(changes, "modified", modified_features)
    else
      changes
    end

    changes
  end

  # Helper function to format changeset errors
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
