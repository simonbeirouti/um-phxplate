defmodule Core.PubSub.DataSync do
  @moduledoc """
  Centralized module for managing live data synchronization across the application.
  Uses Phoenix.PubSub for real-time updates.

  ## Topics
  - users:ID or users:all
  - subscriptions:ID or subscriptions:all
  - plans:ID or plans:all
  - profiles:ID or profiles:all

  ## Events
  - {:created, data}
  - {:updated, data}
  - {:deleted, id}
  - {:status_changed, data}
  - {:error, reason}

  ## Usage Examples

      # Subscribe to updates
      DataSync.subscribe("users", user_id)
      DataSync.subscribe("subscriptions", "all")

      # Broadcast updates
      DataSync.broadcast("users", user_id, {:updated, updated_user})
      DataSync.broadcast("subscriptions", "all", {:created, new_subscription})
  """

  alias Phoenix.PubSub
  require Logger

  @pubsub_server Core.PubSub

  @doc """
  Subscribe to updates for a specific topic and ID.
  The ID can be a specific ID or "all" for all updates of that topic.
  """
  def subscribe(topic, id) when is_binary(topic) do
    topic_name = topic_name(topic, id)
    Logger.debug("Subscribing to topic: #{topic_name}")
    PubSub.subscribe(@pubsub_server, topic_name)
  end

  @doc """
  Broadcast a message to all subscribers of a topic.
  """
  def broadcast(topic, id, message) when is_binary(topic) do
    topic_name = topic_name(topic, id)
    Logger.debug("Broadcasting to topic: #{topic_name}, message: #{inspect(message)}")
    PubSub.broadcast(@pubsub_server, topic_name, message)
  end

  @doc """
  Broadcast a message to all subscribers except the given socket_id.
  Useful for preventing echo effects in real-time updates.
  """
  def broadcast_from(socket_id, topic, id, message) when is_binary(topic) do
    topic_name = topic_name(topic, id)
    Logger.debug("Broadcasting from #{socket_id} to topic: #{topic_name}")
    PubSub.broadcast_from(@pubsub_server, socket_id, topic_name, message)
  end

  @doc """
  Unsubscribe from a topic.
  Should be called in terminate callbacks of LiveViews to prevent memory leaks.
  """
  def unsubscribe(topic, id) when is_binary(topic) do
    topic_name = topic_name(topic, id)
    Logger.debug("Unsubscribing from topic: #{topic_name}")
    PubSub.unsubscribe(@pubsub_server, topic_name)
  end

  # Private helper to generate consistent topic names
  defp topic_name(topic, id), do: "#{topic}:#{id}"
end
