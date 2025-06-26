defmodule Public.UserSessionHandlerLive do
  @moduledoc """
  LiveComponent for handling user session events.

  This component subscribes to user-specific PubSub topics to handle session-related
  events like forced logouts due to account deletion or security concerns. It renders
  an invisible div with a JavaScript hook that can trigger client-side session termination.
  """
  use Public, :live_component
  alias Phoenix.PubSub

  @doc """
  Updates the component and subscribes to user-specific PubSub topics.

  When the component is connected and a current user is present, subscribes to
  a PubSub topic specific to the user's ID to receive session-related messages.
  """
  @impl true
  def update(%{current_user: current_user} = _assigns, socket) do
    if connected?(socket) and current_user do
      # Only subscribe if we have a current_user with an id
      if current_user.id do
        PubSub.subscribe(Core.PubSub, "users:#{current_user.id}")
      end
    end

    {:ok, assign(socket, current_user: current_user)}
  end

  @doc """
  Handles the force logout message by triggering a client-side logout event.

  When a force logout message is received, pushes a JavaScript event that the
  ForceLogout hook will handle to terminate the user's session on the client side.
  """
  def handle_info({:force_logout, _payload}, socket) do
    {:noreply, push_event(socket, "js_force_logout", %{reason: "user_deleted"})}
  end

  @doc """
  Renders an invisible div with a JavaScript hook for handling forced logouts.

  The div has a unique ID based on the component ID and is linked to a JavaScript hook
  that can process logout events. The element is hidden from view since it's only
  needed for its JavaScript functionality.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div id={"user-session-handler-#{@myself.cid}"} phx-hook="ForceLogout" style="display: none;"></div>
    """
  end
end
