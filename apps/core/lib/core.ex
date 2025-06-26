defmodule Core do
  @moduledoc """
  Core business logic and database layer for the umbrella application.

  This module provides the main API for interacting with the database
  and core business logic across all Phoenix applications in the umbrella.
  """

  alias Core.Repo

  @doc """
  Returns the repo module for this application.
  """
  def repo, do: Repo

  @doc """
  Hello world.

  ## Examples

      iex> Core.hello()
      :world

  """
  def hello do
    :world
  end
end
