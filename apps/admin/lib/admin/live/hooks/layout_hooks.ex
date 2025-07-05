defmodule Admin.Live.Hooks.LayoutHooks do
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
          # Hide main nav in dashboard
          |> assign(:show_nav, false)
          |> assign(:dashboard_user, user)
          |> assign(:dashboard_nav, dashboard_navigation_items(user))
          # Ensure current_user has profile loaded
          |> assign(:current_user, user)
          # Default path
          |> assign(:current_path, "/dashboard")

        {:cont, socket}
    end
  end

  @doc """
  Returns the navigation items for the dashboard based on user permissions.
  """
  defp dashboard_navigation_items(_user) do
    [
      %{
        title: "Platform Management",
        items: [
          %{
            label: "Dashboard",
            path: "/dashboard/super_admin",
            icon: "hero-home",
            active_paths: ["/dashboard/super_admin"]
          },
          %{
            label: "Subscriptions",
            path: "/dashboard/super_admin/subscriptions",
            icon: "hero-credit-card",
            active_paths: ["/dashboard/super_admin/subscriptions"]
          },
          %{
            label: "Blogs",
            path: "/dashboard/super_admin/blogs",
            icon: "hero-document-text",
            active_paths: ["/dashboard/super_admin/blogs"]
          },
          %{
            label: "Companies",
            path: "/dashboard/super_admin/companies",
            icon: "hero-building-office",
            active_paths: ["/dashboard/super_admin/companies"]
          },
          %{
            label: "Settings",
            path: "/dashboard/super_admin/platform-settings",
            icon: "hero-cog-6-tooth",
            active_paths: ["/dashboard/super_admin/platform-settings"]
          }
        ]
      },
      %{
        title: "Customer Engagement",
        items: [
          %{
            label: "Support Chat",
            path: "/dashboard/super_admin/chat",
            icon: "hero-chat-bubble-left-right",
            active_paths: ["/dashboard/super_admin/chat"]
          },
          %{
            label: "Feature/Feedback",
            path: "/dashboard/super_admin/feature-feedbacks",
            icon: "hero-light-bulb",
            active_paths: ["/dashboard/super_admin/feature-feedbacks"]
          },
          %{
            label: "Users",
            path: "/dashboard/super_admin/users",
            icon: "hero-users",
            active_paths: ["/dashboard/super_admin/users"]
          }
        ]
      },
      %{
        title: "AI Management",
        items: [
          %{
            label: "AI Chat",
            path: "/dashboard/super_admin/ai-chat",
            icon: "hero-cpu-chip",
            active_paths: ["/dashboard/super_admin/ai-chat"]
          },
          %{
            label: "AI Prompts",
            path: "/dashboard/super_admin/ai-prompts",
            icon: "hero-command-line",
            active_paths: ["/dashboard/super_admin/ai-prompts"]
          },
          %{
            label: "AI Evaluations",
            path: "/dashboard/super_admin/ai-evals",
            icon: "hero-chart-bar",
            active_paths: ["/dashboard/super_admin/ai-evals"]
          },
          %{
            label: "AI Eval Results",
            path: "/dashboard/super_admin/ai-eval-results",
            icon: "hero-chart-pie",
            active_paths: ["/dashboard/super_admin/ai-eval-results"]
          },
          %{
            label: "AI Results",
            path: "/dashboard/super_admin/ai-results",
            icon: "hero-clipboard-document-list",
            active_paths: ["/dashboard/super_admin/ai-results"]
          }
        ]
      }
    ]
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
