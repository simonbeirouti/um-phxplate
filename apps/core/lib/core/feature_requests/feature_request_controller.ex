defmodule Core.FeatureRequests.FeatureRequestController do
  @moduledoc """
  Controller for handling feature request business logic.

  This module separates the business logic from the LiveView component,
  making it easier to test and maintain.
  """
  alias Core.FeatureRequests
  alias Core.FeatureRequests.FeatureRequest

  @doc """
  Creates a new feature request.

  Returns `{:ok, feature_request}` on success or `{:error, changeset}` on failure.
  """
  def create_feature_request(params) do
    FeatureRequests.create_feature_request(params)
  end

  @doc """
  Validates a feature request changeset.

  Returns a changeset with validation results.
  """
  def validate_feature_request(params) do
    %FeatureRequest{}
    |> FeatureRequests.change_feature_request(params)
    |> Map.put(:action, :validate)
  end

  @doc """
  Checks if a feature request form is valid based on its fields.

  Returns true if all required fields are present and valid, false otherwise.
  """
  def form_valid?(priority, request_type, feature_description) do
    priority != nil &&
      request_type != nil &&
      feature_description != nil &&
      feature_description != "" &&
      String.length(feature_description || "") >= 20
  end

  @doc """
  Returns a human-readable label for a priority rating.
  """
  def priority_label(1), do: "Very Low"
  def priority_label(2), do: "Low"
  def priority_label(3), do: "Somewhat Low"
  def priority_label(4), do: "Below Average"
  def priority_label(5), do: "Average"
  def priority_label(6), do: "Above Average"
  def priority_label(7), do: "Somewhat High"
  def priority_label(8), do: "High"
  def priority_label(9), do: "Very High"
  def priority_label(10), do: "Critical"

  @doc """
  Returns a human-readable label for a request type.
  """
  def request_type_label(1), do: "Feature Request"
  def request_type_label(2), do: "Feedback"

  @doc """
  Returns a new empty changeset for a feature request.
  """
  def new_changeset do
    FeatureRequests.change_feature_request(%FeatureRequest{})
  end
end
