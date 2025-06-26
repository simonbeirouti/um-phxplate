defmodule Core.Chat do
  @moduledoc """
  The Chat context.
  Provides functions for managing chat sessions and messages.
  """

  alias Core.Chat.ChatSession
  alias Core.Chat.ChatMessage
  alias Core.Accounts.User
  alias Core.Repo
  alias Phoenix.PubSub

  # Session-related functions

  @doc """
  Creates a new chat session.
  """
  def create_session(attrs) do
    case ChatSession.create_session(attrs) do
      {:ok, session} ->
        # Track chat session creation activity
        track_chat_activity("chat_started", session, nil, %{
          "anonymous_name" => session.anonymous_name,
          "anonymous_email" => session.anonymous_email,
          "device_os" => session.device_os,
          "device_browser" => session.device_browser,
          "device_type" => session.device_type
        })

        {:ok, session}
      error -> error
    end
  end

  @doc """
  Gets a chat session by ID.
  """
  def get_session(id), do: ChatSession.get_session(id)

  @doc """
  Gets a chat session with preloaded messages.
  """
  def get_session_with_messages(id), do: ChatSession.get_session_with_messages(id)

  @doc """
  Lists all active chat sessions.
  """
  def list_active_sessions, do: ChatSession.list_active_sessions()

  @doc """
  Lists chat sessions with pagination support and optional filtering.

  ## Options

    * `:page` - The page number (default: 1)
    * `:per_page` - The number of items per page (default: 10)
    * `:status` - Filter by status ("active" or "closed")
  """
  def list_sessions(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)
    status = Keyword.get(opts, :status)

    filter_opts = if status, do: [status: status], else: []

    ChatSession.list_sessions(page, per_page, filter_opts)
  end

  @doc """
  Returns the total count of chat sessions.
  """
  def count_sessions do
    ChatSession.count_sessions()
  end

  @doc """
  Returns the total count of chat sessions with optional filtering.

  ## Options

    * `:status` - Filter sessions by status ("active" or "closed")
  """
  def count_sessions(opts) do
    ChatSession.count_sessions(opts)
  end

  @doc """
  Closes a chat session.
  """
  def close_session(session) do
    with {:ok, session} <- ChatSession.close_session(session) do
      # Track chat session closure activity
      track_chat_activity("chat_ended", session, nil, %{
        "duration_minutes" => calculate_session_duration(session)
      })

      # Broadcast session closure to all relevant channels
      PubSub.broadcast(Core.PubSub, "chat:session:#{session.id}", {:session_closed, session})
      PubSub.broadcast(Core.PubSub, "admin:chat", {:session_closed, session})

      {:ok, session}
    end
  end

  @doc """
  Gets all chat sessions for a user.
  """
  def get_user_sessions(user_id), do: ChatSession.get_sessions_for_user(user_id)

  @doc """
  Gets all chat sessions for an anonymous user by email.
  """
  def get_anonymous_sessions(email), do: ChatSession.get_sessions_for_anonymous(email)

  # Message-related functions

  @doc """
  Creates a message in a chat session with offline email notification logic.
  Handles real-time broadcasting and offline support notifications.
  """
    def create_message(session_id, content, sender_type) do
    attrs = %{
      chat_session_id: session_id,
      content: content,
      sender_type: sender_type
    }

    case ChatMessage.create_message(attrs) do
      {:ok, message} ->
        # Get session for broadcast context
        session = get_session(session_id)

        # Check if this is a user message while support is offline
        if sender_type == "user" and Core.SupportStatus.get_status() == "offline" do
          # Track offline message activity
          track_chat_activity("chat_message_offline", session, nil, %{
            "message_preview" => String.slice(content, 0, 50),
            "support_status" => "offline"
          })

          # Only send email for the first substantial message (40+ characters) during offline period
          if should_send_offline_email?(session_id, content) do
            # Send email notification to support team
            customer_name = session.anonymous_name || "User #{session.id}"
            customer_email = session.anonymous_email || "No email provided"

            Core.Accounts.UserNotifier.deliver_offline_support_notification(
              customer_email,
              customer_name,
              content,
              session_id
            )

            # Track email notification activity
            track_chat_activity("email_sent", session, nil, %{
              "notification_type" => "offline_support",
              "recipient" => "support_team"
            })
          end
        end

        # Broadcast the message
        Phoenix.PubSub.broadcast(
          Core.PubSub,
          "chat:session:#{session_id}",
          {:new_message, message}
        )

        # Also broadcast to admin topic for real-time updates
        Phoenix.PubSub.broadcast(
          Core.PubSub,
          "admin:chat",
          {:new_message, message}
        )

        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Creates a message in a chat session (backward compatibility version).
  Accepts attrs map for backward compatibility with existing channels.
  """
  def create_message(%{chat_session_id: session_id, content: content, sender_type: sender_type} = attrs) do
    # Extract user_id if present and add it to the attrs for message creation
    attrs_with_user_id = if Map.has_key?(attrs, :user_id) do
      attrs
    else
      attrs
    end

    case ChatMessage.create_message(attrs_with_user_id) do
      {:ok, message} ->
        # Get session for broadcast context
        session = get_session(session_id)

        # Check if this is a user message while support is offline
        if sender_type == "user" and Core.SupportStatus.get_status() == "offline" do
          # Track offline message activity
          track_chat_activity("chat_message_offline", session, nil, %{
            "message_preview" => String.slice(content, 0, 50),
            "support_status" => "offline"
          })

          # Only send email for the first substantial message (40+ characters) during offline period
          if should_send_offline_email?(session_id, content) do
            # Send email notification to support team
            customer_name = session.anonymous_name || "User #{session.id}"
            customer_email = session.anonymous_email || "No email provided"

            Core.Accounts.UserNotifier.deliver_offline_support_notification(
              customer_email,
              customer_name,
              content,
              session_id
            )

            # Track email notification activity
            track_chat_activity("email_sent", session, nil, %{
              "notification_type" => "offline_support",
              "recipient" => "support_team"
            })
          end
        end

        # Broadcast the message
        Phoenix.PubSub.broadcast(
          Core.PubSub,
          "chat:session:#{session_id}",
          {:new_message, message}
        )

        # Also broadcast to admin topic for real-time updates
        Phoenix.PubSub.broadcast(
          Core.PubSub,
          "admin:chat",
          {:new_message, message}
        )

        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Gets a message by ID.
  """
  def get_message(id), do: ChatMessage.get_message(id)

  @doc """
  Gets all messages for a session.
  """
  def get_session_messages(session_id), do: ChatMessage.get_messages_for_session(session_id)

  @doc """
  Gets the latest message for a session.
  """
  def get_latest_message(session_id), do: ChatMessage.get_latest_message(session_id)

  @doc """
  Sends a notification about a new chat session to admins.
  """
  def notify_new_session(session) do
    PubSub.broadcast(Core.PubSub, "admin:chat", {:new_session, session})
  end

  @doc """
  Generates a chat transcript for a session.
  """
  def generate_transcript(session_id) do
    session = get_session_with_messages(session_id)

    # Format the transcript
    messages = Enum.map(session.messages, fn message ->
      # Handle both DateTime and NaiveDateTime types
      timestamp = case message.inserted_at do
        %DateTime{} -> message.inserted_at |> DateTime.to_naive() |> NaiveDateTime.to_string()
        %NaiveDateTime{} -> message.inserted_at |> NaiveDateTime.to_string()
      end
      sender = if message.sender_type == "admin", do: "Support Agent", else: get_sender_name(session, message)
      "[#{timestamp}] #{sender}: #{message.content}"
    end)

    # Format the session start time for the header
    session_time = case session.inserted_at do
      %DateTime{} -> session.inserted_at |> DateTime.to_naive() |> NaiveDateTime.to_string()
      %NaiveDateTime{} -> session.inserted_at |> NaiveDateTime.to_string()
    end

    # Join the messages with newlines
    Enum.join(["Chat Transcript - #{session_time}"] ++ messages, "\n")
  end

  @doc """
  Tracks chat session activity for the history timeline.
  """
  def track_chat_activity(action, session, actor, metadata \\ %{}) do
    Core.Tracking.Activity.track(%{
      action: action,
      entity_type: "chat_session",
      entity_id: session.id,
      changes: %{},
      metadata: metadata,
      actor_id: actor && actor.id,
      company_id: nil  # Chat sessions don't belong to companies
    })
  end

  @doc """
  Gets activities for a specific chat session.
  """
  def get_session_activities(session_id, limit \\ 10) do
    Core.Tracking.get_activities_for_entity("chat_session", session_id, limit)
  end

  # Helper function to get the sender name
  defp get_sender_name(session, message) do
    cond do
      message.user_id ->
        user = Repo.get(User, message.user_id)
        user && user.email || "User"
      session.anonymous_name ->
        session.anonymous_name
      true ->
        "User"
    end
  end

  # Helper function to calculate session duration
  defp calculate_session_duration(session) do
    if session.ended_at && session.started_at do
      DateTime.diff(session.ended_at, session.started_at, :minute)
    else
      0
    end
  end

  defp should_send_offline_email?(session_id, content) do
    # Check if message meets minimum character requirement
    if String.length(content) < 40 do
      false
    else
      # Check if we've already sent an email for this session during the current offline period
      # Look for recent email_sent activities for this session
      activities = get_session_activities(session_id, 50)

      # Check if there's been any email sent activity recently (within last hour)
      one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

      recent_email_sent = Enum.any?(activities, fn activity ->
        activity.action == "email_sent" and
        activity.metadata["notification_type"] == "offline_support" and
        DateTime.compare(activity.inserted_at, one_hour_ago) == :gt
      end)

      # Only send email if we haven't sent one recently
      not recent_email_sent
    end
  end
end
