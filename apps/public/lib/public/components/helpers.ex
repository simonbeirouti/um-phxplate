defmodule Public.Helpers do
  @moduledoc false
  use Phoenix.Component

  import Phoenix.Component

  @doc """
  Humanizes an action string by replacing underscores with spaces and capitalizing.

  Used primarily for displaying activity actions in a user-friendly format.

  ## Examples

      iex> humanize_action("role_update")
      "Role Updated"

      iex> humanize_action("company_create")
      "Company Created"
  """
  def humanize_action("role_update"), do: "Role Updated"
  def humanize_action("subscription_status_update"), do: "Subscription Status Updated"
  def humanize_action("subscription_tier_update"), do: "Subscription Tier Updated"
  def humanize_action("company_create"), do: "Company Created"
  def humanize_action("company_update"), do: "Company Updated"
  def humanize_action("profile_create"), do: "Profile Created"
  def humanize_action("profile_update"), do: "Profile Updated"
  def humanize_action("employee_delete"), do: "Employee Deleted"
  def humanize_action("login"), do: "User Logged In"
  def humanize_action("logout"), do: "User Logged Out"
  def humanize_action("chat_started"), do: "Chat Session Started"
  def humanize_action("chat_message_offline"), do: "Message Sent (Support Offline)"
  def humanize_action("chat_ended"), do: "Chat Session Ended"
  def humanize_action("email_sent"), do: "Email Notification Sent"

  def humanize_action(action) when is_binary(action) do
    action
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def humanize_action(action), do: Phoenix.Naming.humanize(action)

  @doc """
  Humanizes a key by replacing underscores with spaces and capitalizing.

  Used primarily for displaying activity change keys in a user-friendly format.

  ## Examples

      iex> humanize_key("first_name")
      "First name"

      iex> humanize_key("email_address")
      "Email address"
  """
  def humanize_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def humanize_key(key), do: Phoenix.Naming.humanize(key)

  @doc """
  Formats activity changes into a human-readable string.

  Takes a map of changes and converts them into a readable format for display
  in activity timelines. Handles different types of changes including simple
  value changes, nested maps, and special formatting for certain fields.

  ## Examples

      iex> format_activity_changes(%{"name" => "John Doe"})
      "Name: John Doe"

      iex> format_activity_changes(%{"first_name" => "John", "last_name" => "Doe"})
      "First name: John, Last name: Doe"

      iex> format_activity_changes(%{"status" => %{"from" => "inactive", "to" => "active"}})
      "Status changed from inactive to active"
  """
  def format_activity_changes(changes) when is_map(changes) and map_size(changes) == 0, do: ""

  def format_activity_changes(changes) when is_map(changes) do
    changes
    |> Enum.map(&format_single_change/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  def format_activity_changes(_), do: ""

  # Helper function to format a single change
  defp format_single_change({key, value}) when is_map(value) do
    cond do
      # Handle "from/to" change format
      Map.has_key?(value, "from") and Map.has_key?(value, "to") ->
        from_val = format_change_value(value["from"])
        to_val = format_change_value(value["to"])
        "#{humanize_key(key)} changed from #{from_val} to #{to_val}"

      # Handle formatted values (like currency)
      Map.has_key?(value, "from_formatted") and Map.has_key?(value, "to_formatted") ->
        "#{humanize_key(key)} changed from #{value["from_formatted"]} to #{value["to_formatted"]}"

      # Handle nested features changes
      key == "features" ->
        format_features_changes(value)

      # Handle other nested maps
      true ->
        nested_changes =
          Enum.map(value, fn {k, v} -> "#{humanize_key(k)}: #{format_change_value(v)}" end)

        "#{humanize_key(key)} - #{Enum.join(nested_changes, ", ")}"
    end
  end

  defp format_single_change({key, value}) do
    "#{humanize_key(key)}: #{format_change_value(value)}"
  end

  # Helper function to format change values
  defp format_change_value(value) when is_binary(value), do: value
  defp format_change_value(value) when is_number(value), do: to_string(value)
  defp format_change_value(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp format_change_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_change_value(value) when is_map(value), do: inspect(value)
  defp format_change_value(nil), do: "none"
  defp format_change_value(value), do: to_string(value)

  # Helper function to format features changes
  defp format_features_changes(features_map) do
    changes = []

    changes =
      if Map.has_key?(features_map, "added") do
        added_features = features_map["added"] |> Map.keys() |> Enum.join(", ")
        ["Added features: #{added_features}" | changes]
      else
        changes
      end

    changes =
      if Map.has_key?(features_map, "removed") do
        removed_features = features_map["removed"] |> Map.keys() |> Enum.join(", ")
        ["Removed features: #{removed_features}" | changes]
      else
        changes
      end

    changes =
      if Map.has_key?(features_map, "modified") do
        modified_count = map_size(features_map["modified"])
        ["Modified #{modified_count} feature(s)" | changes]
      else
        changes
      end

    case changes do
      [] -> "Features updated"
      _ -> Enum.join(Enum.reverse(changes), ", ")
    end
  end
end
