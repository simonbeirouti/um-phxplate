defmodule Core.Bookmarks.Bookmark do
  @moduledoc """
  Schema for user bookmarks.

  This schema represents a bookmark relationship between a user and a company.
  It allows users to save companies they're interested in for quick reference.
  The schema enforces uniqueness to prevent duplicate bookmarks and maintains
  referential integrity through foreign key constraints.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Core.Accounts.User
  alias Core.Companies.Company

  schema "bookmarks" do
    belongs_to :user, User
    belongs_to :company, Company

    timestamps()
  end

  @doc """
  Changeset function for creating or updating a bookmark.

  Validates required fields, uniqueness constraints, and foreign key constraints.
  Ensures that a user can only bookmark a company once.

  ## Parameters
    - bookmark: The bookmark struct to change
    - attrs: Map of attributes to apply to the bookmark
  """
  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [:user_id, :company_id])
    |> validate_required([:user_id, :company_id])
    |> unique_constraint([:user_id, :company_id], message: "Company already bookmarked")
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:company_id)
  end
end
