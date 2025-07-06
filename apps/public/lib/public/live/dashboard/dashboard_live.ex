defmodule Public.DashboardLive do
  @moduledoc """
  Main dashboard LiveView for authenticated users.

  This view serves as the central hub for authenticated users, displaying
  a welcome message, user information, and quick navigation to key features
  like profile management, companies, and bookmarks.
  """
  use Public, :live_view

  on_mount Public.Live.Hooks.LayoutHooks

  alias Public.PageMeta
  alias Core.Accounts
  alias Core.Companies
  alias Core.Bookmarks
  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Get user's profile information
    profile = Accounts.get_profile_by_user_id(user.id)

    # Get user's recent activity data
    recent_companies = Companies.list_companies() |> Enum.take(3)
    bookmarks_count = if user.role == :basic do
      Bookmarks.count_user_bookmarks(user.id)
    else
      0
    end

    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "Dashboard",
        description: "Your personal dashboard",
        url: "/dashboard"
      )
      |> assign(:profile, profile)
      |> assign(:recent_companies, recent_companies)
      |> assign(:bookmarks_count, bookmarks_count)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Welcome Section -->
      <div class="mb-8">
        <.header>
          Welcome back<%= if @profile, do: ", #{@profile.first_name}", else: "" %>!
          <:subtitle>
            Here's what's happening with your account
          </:subtitle>
        </.header>
      </div>

      <!-- Quick Stats -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <!-- Profile Status -->
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <div class="flex items-center">
              <div class="rounded-full bg-primary/20 p-3 mr-4">
                <.icon name="hero-user" class="h-6 w-6 text-primary" />
              </div>
              <div>
                <h3 class="font-semibold text-base-content">Profile</h3>
                <p class="text-sm text-base-content/70">
                  <%= if @profile, do: "Complete", else: "Incomplete" %>
                </p>
              </div>
            </div>
            <%= if !@profile do %>
              <div class="card-actions justify-end mt-4">
                <.link navigate="/onboarding">
                  <button class="btn btn-sm btn-primary">Complete Profile</button>
                </.link>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Role Info -->
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <div class="flex items-center">
              <div class="rounded-full bg-accent/20 p-3 mr-4">
                <.icon name="hero-shield-check" class="h-6 w-6 text-accent" />
              </div>
              <div>
                <h3 class="font-semibold text-base-content">Account Type</h3>
                <p class="text-sm text-base-content/70 capitalize">
                  <%= String.replace(to_string(@current_user.role), "_", " ") %>
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Bookmarks (for basic users) -->
        <%= if @current_user.role == :basic do %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <div class="flex items-center">
                <div class="rounded-full bg-success/20 p-3 mr-4">
                  <.icon name="hero-bookmark" class="h-6 w-6 text-success" />
                </div>
                <div>
                  <h3 class="font-semibold text-base-content">Bookmarks</h3>
                  <p class="text-sm text-base-content/70">
                    <%= @bookmarks_count %> saved
                  </p>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <!-- Companies (for admin users) -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <div class="flex items-center">
                <div class="rounded-full bg-info/20 p-3 mr-4">
                  <.icon name="hero-building-office" class="h-6 w-6 text-info" />
                </div>
                <div>
                  <h3 class="font-semibold text-base-content">Companies</h3>
                  <p class="text-sm text-base-content/70">
                    Manage your companies
                  </p>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Quick Actions -->
      <div class="card bg-base-100 shadow-sm mb-8">
        <div class="card-body">
          <h2 class="card-title mb-4">Quick Actions</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <!-- Profile Management -->
            <%= if @profile do %>
              <.link navigate="/dashboard/account">
                <button class="btn btn-outline w-full">
                  <.icon name="hero-user-circle" class="h-5 w-5 mr-2" />
                  Account Settings
                </button>
              </.link>
            <% else %>
              <.link navigate="/onboarding">
                <button class="btn btn-primary w-full">
                  <.icon name="hero-user-plus" class="h-5 w-5 mr-2" />
                  Complete Profile
                </button>
              </.link>
            <% end %>

            <!-- Role-specific actions -->
            <%= if @current_user.role == :basic do %>
              <.link navigate="/dashboard/bookmarks">
                <button class="btn btn-outline w-full">
                  <.icon name="hero-bookmark" class="h-5 w-5 mr-2" />
                  My Bookmarks
                </button>
              </.link>
            <% else %>
              <.link navigate="/dashboard/admin/companies">
                <button class="btn btn-outline w-full">
                  <.icon name="hero-building-office" class="h-5 w-5 mr-2" />
                  Manage Companies
                </button>
              </.link>
            <% end %>

            <!-- Public sections -->
            <.link navigate="/companies">
              <button class="btn btn-outline w-full">
                <.icon name="hero-magnifying-glass" class="h-5 w-5 mr-2" />
                Browse Companies
              </button>
            </.link>

            <.link navigate="/blog">
              <button class="btn btn-outline w-full">
                <.icon name="hero-document-text" class="h-5 w-5 mr-2" />
                Read Blog
              </button>
            </.link>
          </div>

          <!-- Logout Action -->
          <div class="mt-4 pt-4 border-t border-base-300">
            <.link href="/logout" method="delete" class="w-full">
              <button class="btn btn-outline btn-error w-full">
                <.icon name="hero-arrow-right-on-rectangle" class="h-5 w-5 mr-2" />
                Sign Out
              </button>
            </.link>
          </div>
        </div>
      </div>

      <!-- Recent Companies -->
      <%= if not Enum.empty?(@recent_companies) do %>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <div class="flex items-center justify-between mb-4">
              <h2 class="card-title">Recent Companies</h2>
              <.link navigate="/companies">
                <button class="btn btn-sm btn-ghost">View All</button>
              </.link>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for company <- @recent_companies do %>
                <.link navigate={~p"/companies/#{company.id}"} class="block">
                  <div class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow duration-200">
                    <div class="card-body p-4">
                      <div class="flex items-center space-x-3">
                        <%= if company.logo do %>
                          <img src={company.logo} alt={company.name} class="w-10 h-10 rounded-full object-cover" />
                        <% else %>
                          <div class="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center">
                            <span class="text-sm font-bold text-primary">
                              <%= String.first(company.name) %>
                            </span>
                          </div>
                        <% end %>
                        <div class="flex-1 min-w-0">
                          <h3 class="font-medium text-base-content truncate">
                            <%= company.name %>
                          </h3>
                          <%= if company.description do %>
                            <p class="text-sm text-base-content/70 truncate">
                              <%= company.description %>
                            </p>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  </div>
                </.link>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
