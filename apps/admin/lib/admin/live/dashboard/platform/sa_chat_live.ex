defmodule Admin.ChatLive do
  @moduledoc """
  LiveView for super admin chat management.

  This view provides functionality for super admins to manage chat sessions,
  including viewing and responding to messages, closing sessions, and monitoring
  active chats. It features real-time updates via PubSub subscriptions.
  """
  use Admin, :live_view
  alias Core.Chat
  alias Core.Repo
  alias Core.Accounts
  alias Admin.PageMeta
  alias Admin.Components.ActivityTimelineComponent
  alias Phoenix.LiveView.JS
  import Admin.CoreComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Core.PubSub, "admin:chat")
    end

    # Get current support status
    current_status = Core.SupportStatus.get_status()

    {:ok,
     socket
     |> stream_configure(:messages, dom_id: &"msg-#{&1.id}")
     |> stream(:messages, [])
     |> assign(
       selected_session: nil,
       current_message: "",
       show_drawer: false,
       filter: "Active",
       support_status: current_status,
       session_activities: []
     )
     |> PageMeta.assign_metadata(
       title: "Chat Management",
       description: "Manage customer support chat sessions",
       url: "/dashboard/chat"
     )
     |> load_sessions(1)}
  end

  defp load_sessions(socket, page) do
    per_page = 10
    filter = socket.assigns.filter

    # Convert display text back to database values for filter
    filter_value = case filter do
      "All" -> "all"
      "Active" -> "active"
      "Closed" -> "closed"
      other -> other
    end

    # Apply filter if not "all"
    filter_opts = if filter_value != "all", do: [status: filter_value], else: []

    # Get total count for pagination with filter
    total_sessions = Chat.count_sessions(filter_opts)
    total_pages = max(1, ceil(total_sessions / per_page))

    # Get paginated sessions with filter
    sessions = Chat.list_sessions(Keyword.merge([page: page, per_page: per_page], filter_opts))

    socket
    |> assign(:active_sessions, sessions)
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:per_page, per_page)
  end

  @impl true
  def handle_event("select_session", %{"id" => session_id, "is_mobile" => "true"}, socket) do
    # Mobile view - show drawer
    select_session(session_id, socket, true)
  end

  def handle_event("select_session", %{"id" => session_id}, socket) do
    # Desktop view - don't show drawer
    select_session(session_id, socket, false)
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, show_drawer: false)}
  end

  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    if String.trim(content) != "" && socket.assigns.selected_session do
      session = socket.assigns.selected_session

      attrs = %{
        content: content,
        sender_type: "admin",
        chat_session_id: session.id,
        user_id: socket.assigns.current_user.id
      }

      case Chat.create_message(attrs) do
        {:ok, _message} ->
          {:noreply, assign(socket, current_message: "")}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_message", %{"message" => %{"content" => content}}, socket) do
    {:noreply, assign(socket, current_message: content)}
  end

  def handle_event("filter_sessions", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> load_sessions(1)}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    {:noreply, load_sessions(socket, page)}
  end

  def handle_event("close_session", _params, socket) do
    if socket.assigns.selected_session do
      session = socket.assigns.selected_session

      case Chat.close_session(session) do
        {:ok, updated_session} ->
          # Send transcript email to the user
          send_transcript_email(updated_session)

          # Show a notification that the transcript was sent
          socket = put_flash(socket, :info, "Chat session closed and transcript sent")
          {:noreply, socket}

        {:error, _changeset} ->
          socket = put_flash(socket, :error, "Failed to close chat session")
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_support_status", _params, socket) do
    new_status = if socket.assigns.support_status == "offline", do: "online", else: "offline"

    # Persist the status
    Core.SupportStatus.set_status(new_status)

    # Broadcast to all support status channels
    Admin.Endpoint.broadcast("support:status", "status_changed", %{status: new_status})

    {:noreply, assign(socket, support_status: new_status)}
  end

  # Helper function to send the transcript email
  defp send_transcript_email(session) do
    # Get the recipient email based on the session type (user or anonymous)
    recipient_email =
      cond do
        session.user_id ->
          user = Repo.get(Accounts.User, session.user_id)
          user && user.email

        session.anonymous_email ->
          session.anonymous_email

        true ->
          nil
      end

    # Only send if we have a valid email
    if recipient_email do
      # Send the transcript email in a separate process to not block the LiveView
      Task.start(fn ->
        Accounts.UserNotifier.deliver_chat_transcript(recipient_email, session.id)
      end)
    end
  end

  # Helper function to select a session
  defp select_session(session_id, socket, show_drawer) do
    session_id = String.to_integer(session_id)
    session = Chat.get_session_with_messages(session_id)

    if session do
      messages =
        Enum.map(session.messages, fn msg ->
          %{
            id: msg.id,
            content: msg.content,
            sender_type: msg.sender_type,
            inserted_at: msg.inserted_at
          }
        end)

      # Get session activities for the history tab
      activities = Chat.get_session_activities(session_id, 20)

      {:noreply,
       socket
       |> stream(:messages, messages, reset: true)
       |> assign(
         selected_session: session,
         show_drawer: show_drawer,
         session_activities: activities
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_session, session}, socket) do
    active_sessions = [session | socket.assigns.active_sessions]
    {:noreply, assign(socket, active_sessions: active_sessions)}
  end


  def handle_info({:new_message, message}, socket) do
    # Update messages if this is for the selected session
    if socket.assigns.selected_session &&
         message.chat_session_id == socket.assigns.selected_session.id do
      formatted_message = %{
        id: message.id,
        content: message.content,
        sender_type: message.sender_type,
        inserted_at: message.inserted_at
      }

      {:noreply, stream_insert(socket, :messages, formatted_message)}
    else
      # Update the session in the list to show there's a new message
      {:noreply, socket}
    end
  end

  def handle_info({:session_closed, closed_session}, socket) do
    # Update the session status in the active sessions list
    updated_sessions =
      Enum.map(socket.assigns.active_sessions, fn session ->
        if session.id == closed_session.id do
          %{session | status: "closed"}
        else
          session
        end
      end)

    # If this was the selected session, update it too
    selected_session =
      if socket.assigns.selected_session &&
           socket.assigns.selected_session.id == closed_session.id do
        %{socket.assigns.selected_session | status: "closed"}
      else
        socket.assigns.selected_session
      end

    {:noreply,
     assign(socket, active_sessions: updated_sessions, selected_session: selected_session)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        Chat Management
        <:subtitle>Manage customer support chat sessions</:subtitle>
        <:actions>
          <button
            phx-click="toggle_support_status"
            class={[
              "btn",
              "transition-all duration-200",
              if(@support_status == "online",
                do: "btn-success text-white hover:bg-red-600",
                else: "btn-error hover:bg-green-600 hover:text-white"
              )
            ]}
            onmouseover={"this.textContent = '#{if @support_status == "online", do: "Go offline", else: "Go online"}'"}
            onmouseout={"this.textContent = 'Support #{String.capitalize(@support_status)}'"}
          >
            Support {String.capitalize(@support_status)}
          </button>
        </:actions>
      </.header>

      <div
        class="grid grid-cols-1 lg:grid-cols-3 lg:gap-8 mt-4 h-[calc(100vh-200px)]"
        id="chat-dashboard"
        phx-hook="ChatDashboard"
      >
        <div class="h-[calc(100vh-200px)] col-span-1">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-semibold">Chat Sessions</h2>
            <form phx-change="filter_sessions" class="w-auto">
              <select id="session-filter" name="filter" class="select select-bordered w-32" phx-change="filter_sessions">
                <option value="All" selected={@filter == "All"}>All</option>
                <option value="Active" selected={@filter == "Active"}>Active</option>
                <option value="Closed" selected={@filter == "Closed"}>Closed</option>
              </select>
            </form>
          </div>

          <%= if Enum.empty?(@active_sessions) do %>
            <div class="text-center py-4">
              <p class="text-sm text-base-content/70">No active chat sessions</p>
            </div>
          <% else %>
            <%= for session <- @active_sessions do %>
              <div class={["cursor-pointer", "p-3", "rounded-md", "hover:bg-base-200", "relative", (@selected_session && @selected_session.id == session.id) && "bg-base-200 border-l-4 border-primary"]}>
                <div
                  class="hidden lg:block h-full w-full absolute inset-0"
                  phx-click="select_session"
                  phx-value-id={session.id}
                >
                </div>
                <div
                  class="lg:hidden h-full w-full absolute inset-0"
                  phx-click="select_session"
                  phx-value-id={session.id}
                  phx-value-is_mobile="true"
                >
                </div>
                <div class="flex justify-between items-center">
                  <h4 class="text-sm font-medium text-base-content">
                    <%= if session.user_id do %>
                      {session.user.email}
                    <% else %>
                      {session.anonymous_name}
                    <% end %>
                  </h4>
                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if session.status == "active", do: "badge badge-success", else: "badge badge-ghost"}"}>
                    {session.status}
                  </span>
                </div>
                <div class="mt-1">
                  <p class="text-xs text-base-content/70">
                    Started: {Calendar.strftime(session.started_at, "%B %d, %Y at %H:%M")}
                  </p>
                </div>
              </div>
            <% end %>
          <% end %>
          <%= if @total_pages > 1 do %>
            <div class="mt-4 mb-2">
              <div class="join justify-center">
                <%= if @page > 1 do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={@page - 1}>
                    <.icon name="hero-chevron-left" class="h-4 w-4" />
                  </button>
                <% end %>

                <%= for page_num <- max(1, @page - 2)..min(@total_pages, @page + 2) do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={page_num}>
                    {page_num}
                  </button>
                <% end %>

                <%= if @page < @total_pages do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={@page + 1}>
                    <.icon name="hero-chevron-right" class="h-4 w-4" />
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <div class="hidden lg:block col-span-2 h-[calc(100vh-200px)] overflow-hidden">
          <h2 class="text-xl font-semibold mb-4">Chat Details</h2>
          <%= if @selected_session do %>
            {render_chat_details(assign(assigns, :context, "desktop"))}
          <% else %>
            <div class="bg-base-100 overflow-hidden shadow rounded-lg h-full flex flex-col justify-center items-center">
              <div class="flex flex-col items-center justify-center text-center p-8">
                <.icon name="hero-chat-bubble-oval-left" class="h-16 w-16 text-base-content/40" />
                <h3 class="mt-4 text-lg font-medium text-base-content">No chat session selected</h3>
                <p class="mt-2 text-base text-base-content/70 max-w-md">
                  Select a chat session from the list to view and respond to messages.
                </p>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <div class={["drawer", @show_drawer && "drawer-open"]}>
        <input id="chat-drawer" type="checkbox" class="drawer-toggle" checked={@show_drawer} />
        <div class="drawer-content">
          <!-- Page content here -->
        </div>
        <div class="drawer-side">
          <label for="chat-drawer" class="drawer-overlay" phx-click="close_drawer"></label>
          <div class="menu p-4 w-80 min-h-full bg-base-200 text-base-content">
            <h2 class="text-lg font-bold">Chat Details</h2>
            <%= if @selected_session && @selected_session.anonymous_email do %>
              <p class="text-sm mb-4 flex flex-row items-center justify-between">
                <%= if @selected_session do %>
                  <%= if @selected_session.user_id do %>
                    {@selected_session.user.email}
                  <% else %>
                    {@selected_session.anonymous_name}
                  <% end %>
                <% else %>
                  Chat Session
                <% end %>
                <span class="text-xs text-gray-500">
                  {Calendar.strftime(@selected_session.started_at, "%B %d, %Y at %H:%M")} -
                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if @selected_session.status == "active", do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
                    {@selected_session.status}
                  </span>
                </span>
              </p>
            <% end %>
            <%= if @selected_session do %>
              {render_mobile_chat_details(assigns)}
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Separate function for mobile drawer to ensure proper layout
  defp render_mobile_chat_details(assigns) do
    assigns = assign(assigns, :context, "mobile")

    ~H"""
    <div class="h-[60vh]">
      {render_chat_details(assigns)}
    </div>
    """
  end

  defp render_chat_details(assigns) do
    context = assigns[:context] || "desktop"
    assigns = assign(assigns, :context, context)

    ~H"""
    <div role="tablist" class="tabs tabs-lifted">
      <input type="radio" name="chat_tabs_#{@context}" role="tab" class="tab" aria-label="Chat" checked />
      <div role="tabpanel" class={["tab-content", "bg-base-100", "border-base-300", "rounded-box", "p-6", "flex", "flex-col", @context == "mobile" && "h-[55vh]" || "h-[calc(100vh-300px)]"]}>
        <div class="flex-1 overflow-hidden flex flex-col h-full">
          <div
            class="chat-messages flex-1 overflow-y-auto"
            id={"#{@context}-chat-messages"}
            phx-hook="ScrollChat"
            data-auto-scroll="true"
          >
            <div
              id={"messages-#{@context}"}
              phx-update="stream"
              phx-stream="messages"
              class="space-y-3 p-2"
            >
              <%= for {msg_id, message} <- @streams.messages do %>
                <div
                  class={["flex", message.sender_type == "admin" && "justify-end" || "justify-start"]}
                  id={msg_id}
                >
                  <div class={["max-w-3/4", "px-4", "py-2", "rounded-lg", message.sender_type == "admin" && "bg-info/20" || "bg-base-200"]}>
                    <div class="text-sm">{message.content}</div>
                    <div class="text-xs text-base-content/70 mt-1">
                      {Calendar.strftime(message.inserted_at, "%H:%M")}
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%= if @selected_session.status == "active" do %>
            <div
              class="pt-3 sticky bottom-0 bg-base-100 border-t border-base-300 mt-auto"
              id={"admin-chat-typing-desktop-#{@selected_session.id}"}
              phx-hook="AdminChatTyping"
              data-session-id={@selected_session.id}
            >
              <.form for={%{}} as={:message} phx-submit="send_message" phx-change="update_message">
                <div class="flex items-center gap-2">
                  <input
                    type="text"
                    name="message[content]"
                    value={@current_message}
                    placeholder="Type your message..."
                    class="input input-bordered flex-grow"
                  />
                  <div class="flex-shrink-0 flex gap-2">
                    <button type="submit" class="btn btn-neutral">Send</button>
                    <button phx-click="close_session" class="btn btn-error">
                      <.icon name="hero-hand-raised" class="w-5 h-5" />
                    </button>
                  </div>
                </div>
              </.form>
            </div>
          <% end %>
        </div>
      </div>

      <input type="radio" name="chat_tabs_#{@context}" role="tab" class="tab" aria-label="Information" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <div class="space-y-2 p-2">
          <div>
            <h3 class="text-lg font-medium text-base-content mb-3">Session Information</h3>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <h4 class="text-sm font-medium text-base-content/70">Session ID</h4>
                <p class="mt-1">{@selected_session.id}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Status</h4>
                <div class="mt-1">
                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if @selected_session.status == :active, do: "badge badge-success", else: "badge badge-error"}"}>
                    {@selected_session.status}
                  </span>
                </div>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Started At</h4>
                <p class="mt-1">
                  {Calendar.strftime(@selected_session.started_at, "%B %d, %Y at %I:%M %p")}
                </p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Last Activity</h4>
                <p class="mt-1">
                  <%= if @selected_session.messages && length(@selected_session.messages) > 0 do %>
                    <% latest_message =
                      @selected_session.messages
                      |> Enum.sort_by(fn msg -> msg.inserted_at end, {:desc, NaiveDateTime})
                      |> hd() %>
                    {Calendar.strftime(latest_message.inserted_at, "%B %d, %Y at %I:%M %p")}
                  <% else %>
                    No messages yet
                  <% end %>
                </p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Message Count</h4>
                <p class="mt-1">{length(@selected_session.messages)}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">User Information</h4>
                <p class="mt-1">
                  <%= if @selected_session.user_id do %>
                    User ID: {@selected_session.user_id}
                  <% else %>
                    Anonymous User
                  <% end %>
                </p>
              </div>
            </div>
          </div>

          <div>
            <h3 class="text-lg font-medium text-base-content mb-3">Device Information</h3>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <h4 class="text-sm font-medium text-base-content/70">Operating System</h4>
                <p class="mt-1">{@selected_session.device_os || "Unknown"}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Browser</h4>
                <p class="mt-1">{@selected_session.device_browser || "Unknown"}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Device Type</h4>
                <p class="mt-1">{@selected_session.device_type || "Unknown"}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Screen Resolution</h4>
                <p class="mt-1">{@selected_session.screen_resolution || "Unknown"}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Timezone</h4>
                <p class="mt-1">{@selected_session.timezone || "Unknown"}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">Language</h4>
                <p class="mt-1">{@selected_session.language || "Unknown"}</p>
              </div>

              <div>
                <h4 class="text-sm font-medium text-base-content/70">IP Address</h4>
                <p class="mt-1">{@selected_session.ip_address || "Unknown"}</p>
              </div>

              <div class="col-span-2">
                <h4 class="text-sm font-medium text-base-content/70">User Agent</h4>
                <p class="mt-1 text-sm break-all">{@selected_session.user_agent || "Unknown"}</p>
              </div>
            </div>
          </div>

          <%= if @selected_session.status == "active" do %>
            <div class="py-4 border-t border-base-300">
              <button phx-click="close_session" class="btn btn-error w-full">
                Close Session
              </button>
            </div>
          <% end %>
        </div>
      </div>

      <input type="radio" name="chat_tabs_#{@context}" role="tab" class="tab" aria-label="History" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <div>
        <%= if @selected_session do %>
          <.live_component
            module={ActivityTimelineComponent}
            id={"chat-activity-timeline-#{@selected_session.id}-#{@context}"}
            activities={@session_activities}
            show_timestamps={true}
          />
        <% else %>
          <p class="text-base-content/70 text-center py-4">No session selected</p>
        <% end %>
        </div>
      </div>
    </div>
    """
  end
end
