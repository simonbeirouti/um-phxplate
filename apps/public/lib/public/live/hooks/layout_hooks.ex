defmodule Public.Live.Hooks.LayoutHooks do
  @moduledoc """
  LiveView hooks for dashboard layouts.

  This module provides on_mount hooks that are executed when LiveViews
  are mounted in dashboard layouts. It handles common setup tasks like
  assigning layout-specific data and ensuring proper authentication state.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  @doc """
  Default on_mount hook for dashboard layouts.

  This hook is called when dashboard LiveViews are mounted and handles:
  - Ensuring the user is properly authenticated
  - Setting up any layout-specific assigns
  - Configuring default page metadata
  - Setting up dashboard navigation data

  ## Parameters
    - `:default` - The hook name (required by Phoenix LiveView)
    - `params` - The route parameters
    - `session` - The session data
    - `socket` - The LiveView socket

  ## Returns
    - `{:cont, socket}` to continue the mount process
    - `{:halt, socket}` to halt if there are issues
  """
  def on_mount(:default, _params, _session, socket) do
    # Ensure we have a current user (this should already be handled by auth hooks)
    case socket.assigns[:current_user] do
      nil ->
        # This shouldn't happen if auth hooks are working properly
        {:halt, redirect(socket, to: "/login")}

      user ->
        # Preload user profile for layout
        user = Core.Repo.preload(user, :profile)

        # Set up any default dashboard assigns
        socket =
          socket
          |> assign(:page_title, "Dashboard")
          |> assign(:show_nav, false) # Hide main nav in dashboard
          |> assign(:dashboard_user, user)
          |> assign(:dashboard_nav, dashboard_navigation_items(user))
          |> assign(:current_user, user) # Ensure current_user has profile loaded
          |> assign(:current_path, "/dashboard") # Default path

        {:cont, socket}
    end
  end

  @doc """
  Returns the navigation items for the dashboard based on user permissions.
  """
  defp dashboard_navigation_items(user) do
    # Main dashboard group - accessible to all users
    dashboard_items = [
      %{
        title: "Platform",
        items: [
          %{
            label: "Dashboard",
            path: "/dashboard",
            icon: "hero-home",
            active_paths: ["/dashboard"]
          },
          %{
            label: "Invites",
            path: "/dashboard/invites",
            icon: "hero-user-plus",
            active_paths: ["/dashboard/invites"]
          },
          %{
            label: "Account",
            path: "/dashboard/account",
            icon: "hero-user-circle",
            active_paths: ["/dashboard/account"]
          },
          %{
            label: "Bookmarks",
            path: "/dashboard/basic/bookmarks",
            icon: "hero-bookmark",
            active_paths: ["/dashboard/basic/bookmarks"]
          },
          %{
            label: "Support",
            path: "/dashboard/support",
            icon: "hero-question-mark-circle",
            active_paths: ["/dashboard/support"]
          },
        ]
      }
    ]

    # Add role-based navigation items (admin only)
    role_based_items = get_role_based_navigation(user)

    dashboard_items ++ role_based_items
  end

  defp get_role_based_navigation(user) do
    admin_items = [
      %{
        title: "Admin",
        items: [
          %{
            label: "Admin Dashboard",
            path: "/dashboard/admin",
            icon: "hero-cog-6-tooth",
            active_paths: ["/dashboard/admin"]
          },
          %{
            label: "Companies",
            path: "/dashboard/admin/companies",
            icon: "hero-building-office",
            active_paths: ["/dashboard/admin/companies"]
          }
        ]
      }
    ]

    case user.role do
      :admin -> admin_items
      _ -> []
    end
  end

  @doc """
  Helper function to determine if a navigation item is active based on current path.
  """
  def nav_item_active?(item, current_path) do
    Enum.any?(item.active_paths, fn path ->
      String.starts_with?(current_path, path)
    end)
  end
end
