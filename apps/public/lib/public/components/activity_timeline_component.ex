defmodule Public.Components.ActivityTimelineComponent do
  @moduledoc """
  A live component that displays an activity timeline with pagination support.

  This component shows a chronological list of activities with details about each
  action, including timestamps, changes made, and the actor who performed the action.
  It supports loading more activities through pagination.
  """
  use Public, :live_component
  alias Public.Helpers

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:page, assigns[:page] || 1)
      |> assign(:per_page, assigns[:per_page] || 20)
      |> assign(:has_more, length(assigns.activities) >= (assigns[:per_page] || 20))

    {:ok, socket}
  end

  @impl true
  def handle_event("load_more", _, socket) do
    page = socket.assigns.page + 1
    per_page = socket.assigns.per_page

    # Get next page of activities based on the type
    new_activities =
      case socket.assigns do
        %{user_id: user_id} ->
          Core.Tracking.get_user_activities(user_id, per_page)

        %{company_id: company_id} ->
          Core.Tracking.get_company_activities(company_id, per_page)

        _ ->
          []
      end

    # Check if we have more activities to load
    has_more = length(new_activities) >= per_page

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:has_more, has_more)
     |> update(:activities, &(&1 ++ new_activities))}
  end

  @doc """
  Renders the activity timeline with pagination support.

  Displays a list of activities with their details and a "Load More" button
  if there are more activities to load.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-2">
      <div class="space-y-4">
        <%= for activity <- @activities do %>
          <div class="border-l-2 border-gray-200 pl-4 pb-4">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <p class="font-medium">
                  {Helpers.humanize_action(activity.action)}
                </p>
                <!-- Mobile timestamp - shown below action on mobile -->
                <p class="text-sm text-gray-500 mt-1 lg:hidden">
                  {Calendar.strftime(activity.inserted_at, "%B %d, %Y at %I:%M %p")}
                </p>
                <%= if map_size(activity.changes) > 0 do %>
                  <div class="mt-2 text-sm text-gray-600">
                    <p class="text-gray-700">
                      {Helpers.format_activity_changes(activity.changes)}
                    </p>
                  </div>
                <% end %>
              </div>
              <!-- Desktop timestamp - shown to the right on desktop -->
              <p class="text-sm text-gray-500 hidden lg:block ml-4 flex-shrink-0">
                {Calendar.strftime(activity.inserted_at, "%B %d, %Y at %I:%M %p")}
              </p>
            </div>
            <%= if activity.actor do %>
              <p class="text-sm text-gray-500 mt-1">
                by {activity.actor.email}
              </p>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @has_more do %>
        <div class="mt-6">
          <div class="flex justify-center">
            <button class="btn btn-primary" phx-click="load_more" phx-target={@myself}>
              Load More
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
