defmodule Admin.Dashboard.LayoutComponent do
  @moduledoc """
  LiveComponent for the dashboard layout.

  This component provides a dynamic dashboard navigation and layout
  that can receive real-time updates for user profile changes,
  navigation updates, and other live data.
  """
  use Admin, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="size-full">
      <div class="flex">
        <.live_component
          module={Admin.Dashboard.SidebarComponent}
          id="sidebar"
          dashboard_nav={@dashboard_nav}
          current_path={@current_path}
          dashboard_user={@dashboard_user}
        />

        <div class="flex h-screen min-w-0 grow flex-col overflow-auto">
          <.live_component
            module={Admin.Dashboard.TopbarComponent}
            id="topbar"
            dashboard_user={@dashboard_user}
          />

          <!--  Start: Layout - Content -->
          <div id="layout-content" class="p-6">
            {render_slot(@inner_block)}
          </div>
        </div>
        <.live_component module={Admin.Dashboard.SearchModalComponent} id="search-modal" />
      </div>
    </div>
    """
  end
end
