defmodule Public.Dashboard.InvitesLive do
  @moduledoc """
  LiveView for managing user invitations to companies.

  This view displays all pending invitations for the current user and
  provides functionality to accept invitations. It handles both the
  listing of invitations and the acceptance action, subscribing to
  real-time updates for invitations via PubSub.
  """
  use Public, :live_view

  alias Core.Companies
  alias Core.PubSub.DataSync
  alias Core.Repo
  alias Public.PageMeta

  @doc """
  Initializes the LiveView for the accept action when a token is present.

  Validates the invitation token, accepts the invitation if valid,
  and redirects with an appropriate success or error message.
  """
  @impl true
  def mount(%{"token" => token} = _params, _session, socket) do
    case Companies.get_invitation_by_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid or expired invitation.")
         |> redirect(to: ~p"/dashboard/invites")}

      invitation ->
        case Companies.accept_invitation(invitation, socket.assigns.current_user) do
          {:ok, _employee} ->
            {:ok,
             socket
             |> put_flash(:info, "You have successfully joined #{invitation.company.name}.")
             |> redirect(to: ~p"/dashboard/invites")}

          {:error, _changeset} ->
            {:ok,
             socket
             |> put_flash(:error, "Error accepting invitation.")
             |> redirect(to: ~p"/dashboard/invites")}
        end
    end
  end

  # Mount for the index action (listing invites)
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("user_invitations", socket.assigns.current_user.email)
    end

    pending_invites = Companies.list_user_pending_invitations(socket.assigns.current_user.email)

    {:ok,
     socket
     |> PageMeta.assign_metadata(
       title: "My Invites",
       description: "View and manage your company invitations",
       url: "/dashboard/invites"
     )
     |> assign(:pending_invites, pending_invites)
     |> assign(:layout_data, %{current_path: "/dashboard/invites"})}
  end

  @impl true
  def handle_info({:created, %{type: :invitation, invitation: invitation}}, socket) do
    invitation = Repo.preload(invitation, [:company, :inviter])
    # Only add the invitation if it doesn't already exist in the list
    {:noreply,
     update(socket, :pending_invites, fn invites ->
       if Enum.any?(invites, &(&1.id == invitation.id)) do
         invites
       else
         [invitation | invites]
       end
     end)}
  end

  def handle_info({:updated, %{type: :invitation, invitation: invitation}}, socket) do
    invitation = Repo.preload(invitation, [:company, :inviter])

    {:noreply,
     update(socket, :pending_invites, fn invites ->
       Enum.map(invites, fn inv -> if inv.id == invitation.id, do: invitation, else: inv end)
     end)}
  end

  def handle_info({:deleted, %{type: :invitation, id: invitation_id}}, socket) do
    {:noreply,
     update(socket, :pending_invites, fn invites ->
       Enum.reject(invites, &(&1.id == invitation_id))
     end)}
  end

  # Ignore other events
  def handle_info(_event, socket), do: {:noreply, socket}

  @impl true
  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    socket = update(socket, :layout_data, &Map.put(&1, :current_path, uri.path))

    # Update the layout component with the new path
    send_update(Public.Dashboard.LayoutComponent,
      id: "dashboard-layout",
      current_path: uri.path
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("accept_invitation", %{"id" => invitation_id}, socket) do
    # Convert invitation_id to integer since it comes as string from the template
    invitation_id = String.to_integer(invitation_id)
    invitation = Enum.find(socket.assigns.pending_invites, &(&1.id == invitation_id))

    case Companies.accept_invitation(invitation, socket.assigns.current_user) do
      {:ok, _employee} ->
        # Refresh the list of pending invites from the database
        pending_invites =
          Companies.list_user_pending_invitations(socket.assigns.current_user.email)

        {:noreply,
         socket
         |> assign(:pending_invites, pending_invites)
         |> put_flash(:info, "You have successfully joined #{invitation.company.name}.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error accepting invitation.")}
    end
  end

  @doc """
  Renders the invitations view showing pending invitations.

  Displays a list of pending company invitations with information about
  the company, inviter, and date sent. Provides buttons to accept each
  invitation. Shows a message if no invitations exist.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        My Invites
        <:subtitle>View and manage your company invitations</:subtitle>
      </.header>

      <div class="mt-8">
        <%= if Enum.empty?(@pending_invites) do %>
          <div class="text-center py-12">
            <div class="mx-auto h-12 w-12 text-gray-400">
              <.icon name="hero-envelope-open" class="w-12 h-12" />
            </div>
            <h3 class="mt-2 text-sm font-semibold text-gray-900">No pending invites</h3>
            <p class="mt-1 text-sm text-gray-500">You don't have any pending company invitations.</p>
          </div>
        <% else %>
          <div class="grid gap-4">
            <%= for invite <- @pending_invites do %>
              <div class="bg-white shadow rounded-lg p-6">
                <div class="flex items-center justify-between">
                  <div>
                    <h3 class="text-lg font-semibold text-gray-900">
                      {invite.company.name}
                    </h3>
                    <p class="text-sm text-gray-500">
                      Invited by {invite.inviter.email}
                    </p>
                    <p class="text-sm text-gray-500">
                      Sent {Calendar.strftime(invite.inserted_at, "%B %d, %Y")}
                    </p>
                  </div>
                  <div>
                    <button
                      phx-click="accept_invitation"
                      phx-value-id={invite.id}
                      class="btn btn-primary"
                    >
                      Accept Invitation
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
