defmodule Public.Dashboard.Account.ActivitiesLive do
  @moduledoc """
  LiveComponent for displaying user activity history.

  This component is responsible for rendering a user's activity timeline
  by leveraging the ActivityTimelineComponent.
  """
  use Public, :live_view
  alias Public.Components.ActivityTimelineComponent

  @doc """
  Updates the component with the provided assigns.

  Sets default values for the show_timestamps flag to control
  timestamp display in the activity timeline.
  """
  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:show_timestamps, false)}
  end

  @doc """
  Renders the activity timeline for the user.

  Uses the ActivityTimelineComponent to display a list of user activity events.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={ActivityTimelineComponent}
        id={"activity-timeline-#{@user.id}"}
        activities={@activities}
        user_id={@user.id}
        show_timestamps={false}
      />
    </div>
    """
  end
end
