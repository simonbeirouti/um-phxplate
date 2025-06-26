defmodule Public.Components.NavComponent do
  @moduledoc """
  Provides the main navigation component for the application.

  This component renders the application's navigation bar with links to public pages,
  sign in/sign up buttons for unauthenticated users, and a dashboard link for
  authenticated users. It also includes a responsive mobile menu.
  """
  use Public, :html

  attr :current_user, :any, doc: "The current user (if authenticated)"
  attr :current_path, :string, doc: "The current path to determine active state"

  @doc """
  Renders the navigation bar with appropriate links based on authentication state.

  Displays public links and authentication controls. The nav is not shown on dashboard pages.
  Includes a responsive mobile menu for smaller screens.
  """
  def nav(assigns) do
    public_links = [
      %{href: ~p"/about", label: "About"},
      %{href: ~p"/companies", label: "Companies"},
      %{href: ~p"/blog", label: "Blog"},
      %{href: ~p"/pricing", label: "Pricing"},
      %{href: ~p"/contact", label: "Contact"}
    ]

    show_nav = !String.starts_with?(assigns.current_path, "/dashboard")
    assigns = assign(assigns, :show_nav, show_nav)
    assigns = assign(assigns, :public_links, public_links)

    ~H"""
    <nav :if={@show_nav} class="fixed sticky top-0 z-50 w-full border-b border-base-200 bg-base-100">
      <div class="mx-auto flex max-w-7xl items-center justify-between px-4 py-4 sm:px-6 lg:px-8">
        <div class="flex items-center">
          <.link href={~p"/"} class="flex items-center space-x-2">
            <span class="text-xl font-bold text-base-content">{Public.config(:title)}</span>
          </.link>
        </div>

        <div class="flex items-center space-x-4">
          <div class="hidden md:flex md:items-center space-x-4">
            <%= for link <- @public_links do %>
              <.link href={link.href} class="text-sm font-medium text-base-content hover:text-primary">
                {link.label}
              </.link>
            <% end %>
          </div>

          <div class="hidden md:flex md:items-center">
            <.theme_toggle />
            <%= if @current_user do %>
              <.link href={~p"/dashboard"}>
                <button class="btn btn-primary ml-2">Dashboard</button>
              </.link>
            <% else %>
              <.link href={~p"/register"}>
                <button class="btn btn-accent mx-2">Sign up</button>
              </.link>
              <.link href={~p"/login"}>
                <button class="btn btn-accent">Sign in</button>
              </.link>
            <% end %>
          </div>
        </div>

        <div class="md:hidden flex items-center">
          <.theme_toggle />
          <button
            type="button"
            class="btn btn-ghost ml-2"
            phx-hook="NavMenu"
            id="nav-menu-button"
          >
            <span class="sr-only">Open main menu</span>
            <.icon name="hero-bars-3" class="h-6 w-6 -mx-2" id="menu-icon" />
            <.icon name="hero-x-mark" class="h-6 w-6 -mx-2 hidden" id="close-icon" />
          </button>
        </div>
      </div>

      <div id="mobile-menu" class="hidden md:hidden absolute w-full bg-base-100 border-b border-base-200 shadow-lg" phx-hook="NavMenu">
        <div class="space-y-2 p-2">
          <%= for link <- @public_links do %>
            <.link
              href={link.href}
              class="block rounded-md px-3 py-2 text-base font-medium text-base-content hover:bg-base-200"
            >
              {link.label}
            </.link>
          <% end %>
          <%= if @current_user do %>
            <.link class="w-full" href={~p"/dashboard"}>
              <button class="btn btn-primary mt-2 w-full">Dashboard</button>
            </.link>
          <% else %>
            <div class="flex items-center space-x-2 w-full">
              <.link href={~p"/register"} class="w-full">
                <button class="btn btn-accent w-full">Sign up</button>
              </.link>
              <.link href={~p"/login"} class="w-full">
                <button class="btn btn-accent w-full">Sign in</button>
              </.link>
            </div>
          <% end %>
        </div>
      </div>
    </nav>
    """
  end
end
