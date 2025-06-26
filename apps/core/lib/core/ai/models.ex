defmodule Core.AI.Models do
  @moduledoc """
  Shared configuration for available AI models.

  This module centralizes the list of available Claude models and their API identifiers,
  making it easy to maintain and update across the application.
  """

  @available_models [
    # Anthropic Claude models
    {"Haiku 3", "claude-3-haiku-20240307"},
    {"Sonnet 3", "claude-3-sonnet-20240229"},
    {"Opus 3", "claude-3-opus-20240229"},
    {"Haiku 3.5", "claude-3-5-haiku-20241022"},
    {"Sonnet 3.5", "claude-3-5-sonnet-20241022"},
    {"Sonnet 3.7", "claude-3-7-sonnet-20250219"},
    {"Sonnet 4", "claude-sonnet-4-20250514"},
    {"Opus 4", "claude-opus-4-20250514"},

    # OpenAI models
    {"GPT-4o", "gpt-4o"},
    {"GPT-4o mini", "gpt-4o-mini"},
    {"GPT-4 Turbo", "gpt-4-turbo"},
    {"GPT-4", "gpt-4"},
    {"GPT-3.5 Turbo", "gpt-3.5-turbo"}
  ]

  @doc """
  Returns the list of available models as {display_name, api_id} tuples.
  """
  def available_models, do: @available_models

  @doc """
  Returns a map of display names to API IDs for easy lookup.
  """
  def display_name_to_api_id do
    @available_models
    |> Enum.into(%{})
  end

  @doc """
  Returns a map of API IDs to display names for reverse lookup.
  """
  def api_id_to_display_name do
    @available_models
    |> Enum.map(fn {display, api} -> {api, display} end)
    |> Enum.into(%{})
  end

  @doc """
  Gets the API ID for a given display name.
  Returns the display name itself if not found (for backward compatibility).
  """
  def get_api_id(display_name) do
    display_name_to_api_id()
    |> Map.get(display_name, display_name)
  end

  @doc """
  Gets the display name for a given API ID.
  Returns the API ID itself if not found (for backward compatibility).
  """
  def get_display_name(api_id) do
    api_id_to_display_name()
    |> Map.get(api_id, api_id)
  end

  @doc """
  Returns the default model API ID.
  """
  def default_model_api_id, do: "claude-3-5-haiku-20241022"

  @doc """
  Returns the default model display name.
  """
  def default_model_display_name, do: "Haiku 3.5"

  @doc """
  Returns the judge model API ID for evaluation scoring.
  Uses the most capable model for accurate judgment.
  """
  def judge_model_api_id, do: "claude-sonnet-4-20250514"

  @doc """
  Returns the judge model display name.
  """
  def judge_model_display_name, do: "Sonnet 4"

  @doc """
  Validates if a given API ID is supported.
  """
  def valid_api_id?(api_id) do
    api_id in Enum.map(@available_models, fn {_, api} -> api end)
  end

  @doc """
  Validates if a given display name is supported.
  """
  def valid_display_name?(display_name) do
    display_name in Enum.map(@available_models, fn {display, _} -> display end)
  end

  @doc """
  Determines if a model API ID is an Anthropic Claude model.
  """
  def anthropic_model?(api_id) do
    String.starts_with?(api_id, "claude-")
  end

  @doc """
  Determines if a model API ID is an OpenAI model.
  """
  def openai_model?(api_id) do
    String.starts_with?(api_id, "gpt-")
  end

  @doc """
  Gets the provider name for a given API ID.
  Returns :anthropic, :openai, or :unknown.
  """
  def get_provider(api_id) do
    cond do
      anthropic_model?(api_id) -> :anthropic
      openai_model?(api_id) -> :openai
      true -> :unknown
    end
  end
end
