defmodule Public.Dashboard.LayoutComponent do
  @moduledoc """
  LiveComponent for the dashboard layout.

  This component provides a dynamic dashboard navigation and layout
  that can receive real-time updates for user profile changes,
  navigation updates, and other live data.
  """
  use Public, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <!-- Dashboard Navigation -->
      <div class="sticky top-0 z-40 bg-base-100 border-b border-base-300">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="navbar">
            <div class="navbar-start">
              <div class="dropdown">
                <div tabindex="0" role="button" class="btn btn-ghost lg:hidden">
                  <.icon name="hero-bars-3" class="h-5 w-5" />
                </div>
                <ul tabindex="0" class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-52">
                  <%= for item <- @dashboard_nav || [] do %>
                    <li>
                      <.link
                        navigate={item.path}
                        class={["flex items-center gap-2", if(String.starts_with?(@current_path || "", item.path), do: "active", else: "")]}
                      >
                        <.icon name={item.icon} class="h-4 w-4" />
                        <%= item.label %>
                      </.link>
                    </li>
                  <% end %>
                </ul>
              </div>
              <.link navigate="/dashboard" class="btn btn-ghost text-xl">Dashboard</.link>
            </div>

            <div class="navbar-center hidden lg:flex">
              <ul class="menu menu-horizontal px-1">
                <%= for item <- @dashboard_nav || [] do %>
                  <li>
                    <.link
                      navigate={item.path}
                      class={["flex items-center gap-2", if(String.starts_with?(@current_path || "", item.path), do: "active", else: "")]}
                    >
                      <.icon name={item.icon} class="h-4 w-4" />
                      <%= item.label %>
                    </.link>
                  </li>
                <% end %>
              </ul>
            </div>

            <div class="navbar-end">
              <div class="dropdown dropdown-end">
                <div tabindex="0" role="button" class="btn btn-ghost btn-circle avatar">
                  <div class="w-10 rounded-full">
                    <%= if @current_user && @current_user.profile && @current_user.profile.avatar_url do %>
                      <img alt="User avatar" src={@current_user.profile.avatar_url} />
                    <% else %>
                      <div class="bg-primary text-primary-content w-10 h-10 rounded-full flex items-center justify-center">
                        <.icon name="hero-user" class="h-5 w-5" />
                      </div>
                    <% end %>
                  </div>
                </div>
                <ul tabindex="0" class="mt-3 z-[1] p-2 shadow menu menu-sm dropdown-content bg-base-100 rounded-box w-52">
                  <li>
                    <.link navigate="/dashboard/account" class="justify-between">
                      Profile
                      <span class="badge">Settings</span>
                    </.link>
                  </li>
                  <li><.link href="/logout" method="delete">Logout</.link></li>
                </ul>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Main Content Area -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= render_slot(@inner_block) %>
      </main>
    </div>
    """
  end
end
