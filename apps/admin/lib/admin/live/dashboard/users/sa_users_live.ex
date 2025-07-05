defmodule Admin.UsersLive do
  @moduledoc """
  LiveView for super admin user management.

  This view provides comprehensive functionality for super admins to manage users,
  including viewing user profiles, changing roles, managing subscriptions,
  viewing activity timelines, and deleting user accounts. It features real-time
  updates via PubSub subscriptions and a paginated user list.
  """
  use Admin, :live_view
  alias Core.{Accounts, Repo, Companies}
  alias Admin.{PageMeta, Components.ActivityTimelineComponent}
  alias Core.PubSub.DataSync

  @impl true
  @doc """
  Initializes the LiveView with paginated users list and subscription data.

  Sets up initial socket assigns with empty values for the selected user,
  available plans, subscription statuses, and paid tier options.
  """
  def mount(_params, _session, socket) do
    plans = Core.Subscriptions.list_all_plans()

    socket =
      socket
      |> assign(:selected_user, nil)
      |> assign(:plans, plans)
      |> assign(:subscription_statuses, [:active, :canceled, :past_due, :incomplete, :trialing])
      |> assign(:paid_tiers, [:none, :small, :medium, :large])
      |> assign(:delete_confirmation, false)
      |> assign(:show_drawer, false)

    {:ok, load_users(socket, 1)}
  end

  defp load_users(socket, page) do
    per_page = 10

    # Get total count for pagination
    total_users = Accounts.count_users()
    total_pages = max(1, ceil(total_users / per_page))

    # Get paginated users
    users =
      Accounts.list_users(page: page, per_page: per_page)
      |> Repo.preload([:profile, :subscription])

    socket
    |> assign(:users, users)
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:per_page, per_page)
    |> PageMeta.assign_metadata(
      title: "User Management",
      description: "Manage users across the application",
      url: "/dashboard/super_admin/users"
    )
  end

  @impl true
  def handle_event("select_user", %{"id" => user_id}, socket) do
    user = Accounts.get_user!(user_id) |> Repo.preload([:profile, :subscription])
    activities = Core.Tracking.get_user_activities(user_id, 20)
    {:noreply, assign(socket, selected_user: user, activities: activities, show_drawer: true)}
  end

  def handle_event("update_role", %{"role" => role, "user_id" => user_id}, socket) do
    role = String.to_existing_atom(role)
    user = Accounts.get_user!(user_id)

    case Accounts.update_user(user, %{role: role}, socket.assigns.current_user) do
      {:ok, updated_user} ->
        # Reload the user with associations
        updated_user = Repo.preload(updated_user, [:profile, :subscription])
        activities = Core.Tracking.get_user_activities(user_id, 20)

        socket =
          socket
          |> assign(:selected_user, updated_user)
          |> assign(:activities, activities)
          |> load_users(socket.assigns.page)
          |> put_flash(:info, "User role updated successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update user role")}
    end
  end

  def handle_event(
        "update_subscription_status",
        %{"user_id" => user_id, "status" => status},
        socket
      ) do
    with %{role: :super_admin} <- socket.assigns.current_user,
         user = Accounts.get_user!(user_id) |> Repo.preload(:subscription),
         status = String.to_existing_atom(status) do
      result =
        if user.subscription do
          Core.Subscriptions.admin_update_subscription_status(user.subscription, status, socket.assigns.current_user)
        else
          # Create a new subscription with basic tier if none exists
          Core.Subscriptions.admin_create_subscription(user_id, :small, status, socket.assigns.current_user)
        end

      case result do
        {:ok, _subscription} ->
          # Reload the user to get the updated subscription
          updated_user = Accounts.get_user!(user_id) |> Repo.preload([:profile, :subscription])
          activities = Core.Tracking.get_user_activities(user_id, 20)

          socket =
            socket
            |> assign(:selected_user, updated_user)
            |> assign(:activities, activities)
            |> load_users(socket.assigns.page)
            |> put_flash(:info, "Subscription status updated successfully")

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update subscription status")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to update subscription status")}
    end
  end

  def handle_event("update_subscription_tier", %{"user_id" => user_id, "tier" => tier}, socket) do
    with %{role: :super_admin} <- socket.assigns.current_user,
         user = Accounts.get_user!(user_id) |> Repo.preload(:subscription),
         tier = String.to_existing_atom(tier) do
      result =
        if tier == :none do
          if user.subscription do
            Core.Subscriptions.admin_update_subscription_tier(user.subscription, tier, socket.assigns.current_user)
          else
            {:ok, nil} # Already has no subscription
          end
        else
          if user.subscription do
            Core.Subscriptions.admin_update_subscription_tier(user.subscription, tier, socket.assigns.current_user)
          else
            # Create a new subscription with the selected tier
            Core.Subscriptions.admin_create_subscription(user_id, tier, :active, socket.assigns.current_user)
          end
        end

      case result do
        {:ok, _subscription} ->
          # Reload the user to get the updated subscription
          updated_user = Accounts.get_user!(user_id) |> Repo.preload([:profile, :subscription])
          activities = Core.Tracking.get_user_activities(user_id, 20)

          socket =
            socket
            |> assign(:selected_user, updated_user)
            |> assign(:activities, activities)
            |> load_users(socket.assigns.page)
            |> put_flash(:info, "Subscription tier updated successfully")

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update subscription tier")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to update subscription tier")}
    end
  end

  def handle_event("delete_user", _params, socket) do
    {:noreply, assign(socket, :delete_confirmation, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_confirmation, false)}
  end

  def handle_event("confirm_delete_user", %{"user_id" => user_id}, socket) do
    with %{role: :super_admin} <- socket.assigns.current_user,
         user = Accounts.get_user!(user_id) |> Repo.preload(:profile),
         {:ok, _deleted} <- Accounts.delete_user(user, socket.assigns.current_user) do
      # Find any associated employee before broadcasting events
      employee = Companies.get_employee_by_user_id(user_id)

      # Broadcast user deletion to all relevant topics
      DataSync.broadcast("users", "all", {:deleted, %{type: :user, id: user_id}})

      # If user has a profile, broadcast profile deletion
      if profile = user.profile do
        DataSync.broadcast("profiles", profile.id, {:deleted, %{type: :profile, id: profile.id}})
      end

      # If we found an employee, broadcast employee deletion
      if employee do
        # Broadcast employee deletion events
        DataSync.broadcast("employees", employee.company_id, {:deleted, %{type: :employee, id: employee.id}})

        # Also broadcast to the specific company channel
        DataSync.broadcast("companies", employee.company_id, {:employee_deleted, %{
          type: :employee,
          id: employee.id,
          user_id: user_id
        }})
      end

      # Broadcast logout event to force the user to log out if they're still logged in
      DataSync.broadcast("users", user_id, {:force_logout, %{type: :user, id: user_id}})

      socket =
        socket
        |> assign(:selected_user, nil)
        |> assign(:delete_confirmation, false)
        |> load_users(socket.assigns.page)
        |> put_flash(:info, "User deleted successfully")

      {:noreply, socket}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to delete user")}
    end
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    {:noreply, load_users(socket, page)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, show_drawer: false)}
  end

  @impl true
  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    socket = update(socket, :layout_data, &Map.put(&1, :current_path, uri.path))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:created, %{type: :profile, profile: new_profile, global_scope: true}}, socket) do
    current_users = socket.assigns.users
    current_selected_user = socket.assigns.selected_user

    updated_users = Enum.map(current_users, fn user_in_list ->
      if user_in_list.id == new_profile.user_id do
        %{user_in_list | profile: new_profile}
      else
        user_in_list
      end
    end)

    updated_selected_user =
      if current_selected_user && current_selected_user.id == new_profile.user_id do
        # Ensure we are creating a new map for selected_user to help LiveView detect the change.
        # Preloading should be handled when the user is initially selected or list is loaded.
        Map.put(current_selected_user, :profile, new_profile)
      else
        current_selected_user
      end

    {:noreply, assign(socket, users: updated_users, selected_user: updated_selected_user)}
  end

  def handle_info({:updated, %{type: :profile, profile: updated_profile, global_scope: true}}, socket) do
    current_users = socket.assigns.users
    current_selected_user = socket.assigns.selected_user

    updated_users = Enum.map(current_users, fn user_in_list ->
      if user_in_list.id == updated_profile.user_id do
        %{user_in_list | profile: updated_profile}
      else
        user_in_list
      end
    end)

    updated_selected_user =
      if current_selected_user && current_selected_user.id == updated_profile.user_id do
        # Ensure we are creating a new map for selected_user.
        Map.put(current_selected_user, :profile, updated_profile)
      else
        current_selected_user
      end

    {:noreply, assign(socket, users: updated_users, selected_user: updated_selected_user)}
  end

  # Handle company deletion events
  def handle_info({:deleted, %{type: :company}}, socket) do
    # Just ignore company deletion events in the users view
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        User Management
        <:subtitle>Manage users across the application</:subtitle>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mt-4 h-[calc(100vh-200px)]">
        <div class="h-[calc(100vh-200px)] col-span-1">
          <h2 class="text-xl font-semibold mb-4">User List</h2>
          <div class="divide-y">
            <%= for user <- @users do %>
              <div class={"cursor-pointer p-3 rounded-md hover:bg-gray-50 relative #{if @selected_user && @selected_user.id == user.id, do: "bg-gray-100 border-l-4 border-blue-500", else: ""}"}
                phx-click="select_user"
                phx-value-id={user.id}
              >
                <!-- User content -->
                <div class="flex justify-between items-center">
                  <h4 class="text-sm font-medium text-gray-900">{user.email}</h4>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                    {user.role}
                  </span>
                </div>
                <div class="mt-1">
                  <p class="text-xs text-gray-500">
                    ID: {user.id} • Created: {Calendar.strftime(user.inserted_at, "%B %d, %Y at %H:%M")}
                  </p>
                </div>
              </div>
            <% end %>
          </div>

          <%= if @total_pages > 1 do %>
            <div class="mt-6">
              <div class="join w-full flex justify-center items-center">
                <%= if @page > 1 do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={@page - 1}>
                    <.icon name="arrow-left" class="w-3.5 h-3.5" />
                  </button>
                <% end %>

                <%= for page_num <- max(1, @page - 2)..min(@total_pages, @page + 2) do %>
                  <button
                    class={"join-item btn #{if page_num == @page, do: "btn-active"}"}
                    phx-click="paginate"
                    phx-value-page={page_num}
                  >
                    {page_num}
                  </button>
                <% end %>

                <%= if @page < @total_pages do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={@page + 1}>
                    <.icon name="arrow-right" class="w-3.5 h-3.5" />
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Desktop Details View (hidden on mobile) -->
        <div class="hidden lg:block col-span-1">
          <h2 class="text-xl font-semibold mb-4">User Details</h2>
          <%= if @selected_user do %>
            <%= render_user_details(assign(assigns, :context, "desktop")) %>
          <% else %>
            <p class="text-gray-500">Select a user to view details</p>
          <% end %>
        </div>
      </div>

      <!-- Mobile Drawer -->
      <div class="lg:hidden">
        <div class={"drawer drawer-bottom #{if @show_drawer and @selected_user != nil, do: "drawer-open"}"}>
          <input id="mobile-user-drawer" type="checkbox" class="drawer-toggle" checked={@show_drawer and @selected_user != nil} />
          <div class="drawer-content">
            <!-- Page content here -->
          </div>
          <div class="drawer-side">
            <label for="mobile-user-drawer" class="drawer-overlay" phx-click="close_drawer"></label>
            <div class="menu p-4 w-full h-3/4 bg-base-200 text-base-content">
              <h2 class="text-lg font-bold">User Details</h2>
              <%= if @selected_user do %>
                <p class="text-sm mb-4">{@selected_user.email}</p>
              <% end %>
              <%= if @selected_user do %>
                <%= render_user_details(assign(assigns, :context, "mobile")) %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Extract the user details rendering into a separate function for reuse
  defp render_user_details(assigns) do
    # Add a context to make component IDs unique
    context = assigns[:context] || "desktop"
    assigns = assign(assigns, :context, context)

    ~H"""
    <div role="tablist" class="tabs tabs-lifted">
      <input type="radio" name="user_tabs_#{@context}" role="tab" class="tab" aria-label="Profile" checked />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <div class="space-y-4 p-2">
          <%= if @selected_user.profile do %>
            <div class="grid grid-cols-2 gap-4">
              <div class="col-span-1 flex items-center justify-center">
                <img
                  class="w-48 h-48 rounded-full"
                  src={@selected_user.profile.avatar_url || ""}
                  alt="Avatar"
                />
              </div>
              <div class="col-span-1 flex flex-col gap-4">
                <div>
                  <h4 class="text-sm font-medium text-gray-500">First Name</h4>
                  <p class="mt-1">{@selected_user.profile.first_name || "Not provided"}</p>
                </div>
                <div>
                  <h4 class="text-sm font-medium text-gray-500">Last Name</h4>
                  <p class="mt-1">{@selected_user.profile.last_name || "Not provided"}</p>
                </div>
                <div>
                  <h4 class="text-sm font-medium text-gray-500">Phone</h4>
                  <p class="mt-1">{@selected_user.profile.phone || "Not provided"}</p>
                </div>
              </div>
              <div class="col-span-2">
                <h4 class="text-sm font-medium text-gray-500">Bio</h4>
                <p class="mt-1">{@selected_user.profile.bio || "Not provided"}</p>
              </div>
              <div class="col-span-1">
                <h4 class="text-sm font-medium text-gray-500">Location</h4>
                <p class="mt-1">{@selected_user.profile.location || "Not provided"}</p>
              </div>
              <div class="col-span-1">
                <h4 class="text-sm font-medium text-gray-500">Website</h4>
                <p class="mt-1">{@selected_user.profile.website || "Not provided"}</p>
              </div>
              <div class="col-span-2">
                <h4 class="text-sm font-medium text-gray-500">Social Links</h4>
                <div class="mt-1 w-full flex justify-between">
                  <%= if @selected_user.profile.social_links && map_size(@selected_user.profile.social_links) > 0 do %>
                    <%= for {platform, url} <- @selected_user.profile.social_links do %>
                      <a
                        href={url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex mr-2 w-full"
                      >
                        <button class="btn flex flex-row items-center gap-2 w-full">
                          <span class="capitalize">{platform}</span>
                          <.icon name="arrow-top-right-on-square" class="w-3.5 h-3.5 ml-2" />
                        </button>
                      </a>
                    <% end %>
                  <% else %>
                    <p>Not provided</p>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <p class="text-gray-500">No profile information available</p>
          <% end %>
        </div>
      </div>

      <input type="radio" name="user_tabs_#{@context}" role="tab" class="tab" aria-label="Account" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <div class="space-y-4 p-2">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <h4 class="text-sm font-medium text-gray-500">Email</h4>
              <p class="mt-1">{@selected_user.email}</p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Account Status</h4>
              <p class="mt-1">
                {if @selected_user.confirmed_at, do: "Confirmed", else: "Pending Confirmation"}
              </p>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <h4 class="text-sm font-medium text-gray-500">Role</h4>
              <form phx-change="update_role" class="mt-2">
                <select
                  id={"role-select-#{@context}"}
                  name="role"
                  class="select select-bordered capitalize w-[180px]"
                  phx-change="update_role"
                >
                  <option value="basic" selected={@selected_user.role == :basic}>Basic</option>
                  <option value="admin" selected={@selected_user.role == :admin}>Admin</option>
                  <option value="super_admin" selected={@selected_user.role == :super_admin}>Super Admin</option>
                </select>
                <input type="hidden" name="user_id" value={@selected_user.id} />
              </form>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Subscription Status</h4>
              <form phx-change="update_subscription_status" class="mt-2">
                <select
                  id={"status-select-#{@context}"}
                  name="status"
                  class="select select-bordered capitalize w-[180px]"
                  phx-change="update_subscription_status"
                >
                  <%= for status <- @subscription_statuses do %>
                    <option
                      value={status}
                      selected={
                        @selected_user.subscription &&
                          @selected_user.subscription.subscription_status == status
                      }
                    >
                      {status}
                    </option>
                  <% end %>
                </select>
                <input type="hidden" name="user_id" value={@selected_user.id} />
              </form>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Current Plan</h4>
              <form phx-change="update_subscription_tier" class="mt-2">
                <select
                  id={"tier-select-#{@context}"}
                  name="tier"
                  class="select select-bordered capitalize w-[180px]"
                  phx-change="update_subscription_tier"
                >
                  <%= for tier <- @paid_tiers do %>
                    <option
                      value={tier}
                      selected={
                        @selected_user.subscription && @selected_user.subscription.paid_tier == tier
                      }
                    >
                      {tier}
                    </option>
                  <% end %>
                </select>
                <input type="hidden" name="user_id" value={@selected_user.id} />
              </form>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Subscription End Date</h4>
              <p class="mt-1">
                <%= if @selected_user.subscription && @selected_user.subscription.subscription_period_end do %>
                  {Calendar.strftime(
                    @selected_user.subscription.subscription_period_end,
                    "%B %d, %Y"
                  )}
                <% else %>
                  N/A
                <% end %>
              </p>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <h4 class="text-sm font-medium text-gray-500">Customer ID</h4>
              <p class="mt-1">
                <%= if @selected_user.subscription do %>
                  {@selected_user.subscription.stripe_customer_id}
                <% else %>
                  No customer ID
                <% end %>
              </p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Subscription ID</h4>
              <p class="mt-1">
                <%= if @selected_user.subscription do %>
                  {@selected_user.subscription.stripe_subscription_id}
                <% else %>
                  No subscription ID
                <% end %>
              </p>
            </div>
          </div>

          <div class="mt-8 border-t pt-6">
            <%= if @delete_confirmation do %>
              <div class="flex w-full justify-between space-x-4">
                <button
                  class="btn btn-error w-full"
                  phx-click="confirm_delete_user"
                  phx-value-user_id={@selected_user.id}
                >
                  Confirm Delete
                </button>
                <button class="btn btn-outline w-full" phx-click="cancel_delete">
                  Cancel
                </button>
              </div>
            <% else %>
              <div class="flex w-full justify-between space-x-4">
                <a class="btn w-full" href={~p"/dashboard/impersonate/#{@selected_user.id}"}>
                  <.icon name="user-circle" class="-ml-0.5 mr-2 h-4 w-4" /> Impersonate User
                </a>
                <button class="btn btn-error w-full" phx-click="delete_user">
                  Delete User Account
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <input type="radio" name="user_tabs_#{@context}" role="tab" class="tab" aria-label="Timeline" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <%= if @selected_user do %>
          <.live_component
            module={ActivityTimelineComponent}
            id={"activity-timeline-user-#{@selected_user.id}-#{@context}"}
            activities={@activities}
            user_id={@selected_user.id}
            show_timestamps={true}
            timestamps={%{
              confirmed_at: @selected_user.confirmed_at,
              inserted_at: @selected_user.inserted_at,
              updated_at: @selected_user.updated_at
            }}
          />
        <% end %>
      </div>
    </div>
    """
  end
end
