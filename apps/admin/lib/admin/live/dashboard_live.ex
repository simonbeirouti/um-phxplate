defmodule Admin.DashboardLive do
  @moduledoc """
  Main dashboard LiveView for authenticated admin users.

  This view serves as the landing page after successful authentication
  and provides navigation to various admin functions.
  """
  use Admin, :live_view
  alias Admin.PageMeta

  @doc """
  Renders the admin dashboard with user information and navigation.
  """
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">

    <!-- Main Content -->
      <div class="container mx-auto px-4 py-8">
        <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          <!-- Welcome Card -->
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-primary">Welcome back!</h2>
              <p class="text-base-content/70">
                You're logged in as <strong>{@current_user.email}</strong>
              </p>
              <%= if @real_user do %>
                <div class="alert alert-info mt-4">
                  <div class="flex items-center gap-2">
                    <.icon name="hero-eye" class="w-4 h-4" />
                    <span class="text-sm">
                      Impersonating user (Real user: {@real_user.email})
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

    <!-- User Management Card -->
          <%= if @current_user.role in [:admin, :super_admin] do %>
            <div class="card bg-base-200 shadow-sm">
              <div class="card-body">
                <h2 class="card-title">User Management</h2>
                <p class="text-base-content/70">Manage user accounts and permissions</p>
                <div class="card-actions justify-end">
                  <button class="btn btn-primary btn-sm" disabled>Coming Soon</button>
                </div>
              </div>
            </div>
          <% end %>

    <!-- System Settings Card -->
          <%= if @current_user.role == :super_admin do %>
            <div class="card bg-base-200 shadow-sm">
              <div class="card-body">
                <h2 class="card-title">System Settings</h2>
                <p class="text-base-content/70">Configure system-wide settings</p>
                <div class="card-actions justify-end">
                  <button class="btn btn-primary btn-sm" disabled>Coming Soon</button>
                </div>
              </div>
            </div>
          <% end %>

    <!-- Analytics Card -->
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h2 class="card-title">Analytics</h2>
              <p class="text-base-content/70">View system analytics and reports</p>
              <div class="card-actions justify-end">
                <button class="btn btn-primary btn-sm" disabled>Coming Soon</button>
              </div>
            </div>
          </div>
        </div>

    <!-- Role-based content -->
        <div class="mt-8">
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h2 class="card-title">Your Permissions</h2>
              <div class="grid gap-4 md:grid-cols-2">
                <div>
                  <h3 class="font-semibold mb-2">
                    Current Role: {String.capitalize(to_string(@current_user.role))}
                  </h3>
                  <ul class="list-disc list-inside text-sm text-base-content/70 space-y-1">
                    <%= case @current_user.role do %>
                      <% :basic -> %>
                        <li>View personal dashboard</li>
                        <li>Update personal profile</li>
                      <% :admin -> %>
                        <li>View personal dashboard</li>
                        <li>Update personal profile</li>
                        <li>Manage users</li>
                        <li>View system reports</li>
                      <% :super_admin -> %>
                        <li>Full system access</li>
                        <li>Manage all users</li>
                        <li>System configuration</li>
                        <li>User impersonation</li>
                    <% end %>
                  </ul>
                </div>
                <div>
                  <h3 class="font-semibold mb-2">Account Status</h3>
                  <div class="space-y-2">
                    <div class="flex items-center gap-2">
                      <div class="badge badge-success badge-sm">Active</div>
                      <span class="text-sm">Account is active</span>
                    </div>
                    <%= if @current_user.confirmed_at do %>
                      <div class="flex items-center gap-2">
                        <div class="badge badge-success badge-sm">Verified</div>
                        <span class="text-sm">Email verified</span>
                      </div>
                    <% else %>
                      <div class="flex items-center gap-2">
                        <div class="badge badge-warning badge-sm">Unverified</div>
                        <span class="text-sm">Email not verified</span>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Initializes the dashboard LiveView with user data and metadata.
  """
  def mount(_params, _session, socket) do
    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "Admin Dashboard",
        description: "Admin dashboard and management interface",
        url: "/dashboard"
      )

    {:ok, socket}
  end
end
