defmodule Admin.Dashboard.TopbarComponent do
  use Admin, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base text-base-content">
      <div
        role="navigation"
        aria-label="Navbar"
        class="flex items-center justify-between px-3"
        id="layout-topbar"
      >
        <div class="inline-flex items-center gap-3">
          <label
            class="btn btn-square btn-ghost btn-md"
            aria-label="Leftmenu toggle"
            for="layout-sidebar-toggle-trigger"
          >
            <.icon name="hero-bars-3" class="size-6" />
          </label>
          <button
            phx-click={JS.dispatch("show", to: "#topbar-search-modal")}
            class="btn btn-outline btn-sm btn-ghost border-base-300 text-base-content/70 hidden h-9 w-48 justify-start gap-2 !text-sm md:flex"
          >
            <.icon name="hero-magnifying-glass" class="size-4" />
            <span>Search</span>
          </button>
          <button
            phx-click={JS.dispatch("show", to: "#topbar-search-modal")}
            class="btn btn-outline btn-sm btn-square btn-ghost border-base-300 text-base-content/70 flex size-9 md:hidden"
            aria-label="Search"
          >
            <.icon name="hero-magnifying-glass" class="size-4" />
          </button>
        </div>
        <div class="inline-flex items-center gap-1.5">
          <.theme_toggle />
        </div>
      </div>
    </div>
    """
  end
end
