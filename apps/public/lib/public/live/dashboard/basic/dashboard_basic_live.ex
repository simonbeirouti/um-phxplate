defmodule Public.Dashboard.Basic.BasicLive do
  @moduledoc """
  LiveView for the basic user dashboard.

  This view provides a simple dashboard for users with basic access level,
  displaying summary statistics like bookmark counts. It subscribes to
  real-time updates for bookmarks via PubSub.
  """
  use Public, :live_view

  alias Public.PageMeta
  alias Core.{Bookmarks, PubSub.DataSync}

  @doc """
  Initializes the LiveView with user's bookmark count.

  Sets up PubSub subscription for bookmark updates and assigns
  the initial bookmark count to the socket.
  """
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("bookmarks", socket.assigns.current_user.id)
    end

    bookmark_count = Bookmarks.count_user_bookmarks(socket.assigns.current_user.id)

    {:ok,
     socket
     |> PageMeta.assign_metadata(
       title: "Basic Dashboard",
       description: "Your personalized dashboard",
       url: "/dashboard/basic"
     )
     |> assign(:bookmark_count, bookmark_count)}
  end

  @doc """
  Handles URL parameters and updates the layout data with current path.
  """
  @impl true
  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    {:noreply, assign(socket, :current_path, uri.path)}
  end

  @impl true
  def handle_info({:created, %{type: :bookmark}}, socket) do
    bookmark_count = Bookmarks.count_user_bookmarks(socket.assigns.current_user.id)
    {:noreply, assign(socket, :bookmark_count, bookmark_count)}
  end

  def handle_info({:deleted, %{type: :bookmark}}, socket) do
    bookmark_count = Bookmarks.count_user_bookmarks(socket.assigns.current_user.id)
    {:noreply, assign(socket, :bookmark_count, bookmark_count)}
  end

  # Ignore other events
  def handle_info(_event, socket), do: {:noreply, socket}

  @doc """
  Renders the basic dashboard view with bookmark statistics.

  Displays a dashboard card showing the user's bookmark count
  with a link to view all bookmarks.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <.header>
        Basic Dashboard
        <:subtitle>View your user stats</:subtitle>
      </.header>
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 mt-4">
        <.link navigate={~p"/dashboard/basic/bookmarks"} class="block">
          <div class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow duration-200">
            <div class="card-body">
              <div class="flex items-center">
                <div class="p-3 bg-primary/10 rounded-lg">
                  <svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-6 w-6 text-primary">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0 1 11.186 0Z" />
                  </svg>
                </div>
                <div class="ml-4">
                  <h3 class="card-title text-base-content">My Bookmarks</h3>
                  <p class="text-2xl font-bold text-primary">
                    {@bookmark_count}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </.link>
      </div>
    </main>
    """
  end
end
