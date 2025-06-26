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
  Gets configuration values for the application.

  ## Examples

      iex> Core.config([:title])
      "PHXPlate"

      iex> Core.config([:email])
      "no-reply@cmpnd.cc"

      iex> Core.config([:support_email])
      "hello@simonbeirouti.com"

      iex> Core.config([:public_base_url])
      "http://localhost:4000"

      iex> Core.config([:admin_base_url])
      "http://localhost:4001"
  """
  def config(key_path) when is_list(key_path) do
    case key_path do
      [:title] -> Application.get_env(:core, :title, "PHXPlate")
      [:email] -> Application.get_env(:core, :email, "no-reply@cmpnd.cc")
      [:support_email] -> Application.get_env(:core, :support_email, "hello@simonbeirouti.com")
      [:description] -> Application.get_env(:core, :description, "Your starting place for a SaaS using Phoenix and Elixir.")
      [:public_base_url] -> Application.get_env(:core, :public_base_url, "http://localhost:4000")
      [:admin_base_url] -> Application.get_env(:core, :admin_base_url, "http://localhost:4001")
      # Keep backward compatibility for base_url (defaults to public)
      [:base_url] -> Application.get_env(:core, :public_base_url, "http://localhost:4000")
      _ -> nil
    end
  end

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
