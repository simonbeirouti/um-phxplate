defmodule Core.Bookmarks do
  @moduledoc """
  The Bookmarks context.

  This context manages the bookmarking functionality that allows users to save
  references to companies they're interested in. It provides functions for creating
  and removing bookmarks, checking bookmark status, and retrieving bookmarked items.
  The context also handles real-time updates through PubSub broadcasts when bookmarks
  are created or deleted.
  """

  import Ecto.Query, warn: false
  alias Core.Repo
  alias Core.Bookmarks.Bookmark
  alias Core.PubSub.DataSync

  @doc """
  Returns the list of bookmarks for a user.

  Retrieves all bookmarks created by a specific user, with the associated
  company data preloaded.

  ## Parameters
    - user_id: The ID of the user whose bookmarks to retrieve

  ## Returns
    - List of bookmark records with associated companies
  """
  def list_user_bookmarks(user_id) do
    Bookmark
    |> where(user_id: ^user_id)
    |> preload(:company)
    |> Repo.all()
  end

  @doc """
  Gets a single bookmark by user and company.

  Retrieves a specific bookmark based on the user who created it and
  the company that was bookmarked.

  ## Parameters
    - user_id: The ID of the user who created the bookmark
    - company_id: The ID of the bookmarked company

  ## Returns
    - The bookmark record if found
    - nil if no matching bookmark exists
  """
  def get_bookmark(user_id, company_id) do
    Bookmark
    |> where(user_id: ^user_id, company_id: ^company_id)
    |> Repo.one()
  end

  @doc """
  Creates a bookmark.

  Creates a new bookmark relationship between a user and a company.
  Broadcasts the creation event to relevant PubSub topics for real-time updates.

  ## Parameters
    - attrs: Map containing user_id and company_id for the bookmark

  ## Returns
    - `{:ok, bookmark}` on success
    - `{:error, changeset}` on validation failure (e.g., when bookmark already exists)
  """
  def create_bookmark(attrs \\ %{}) do
    %Bookmark{}
    |> Bookmark.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, bookmark} = result ->
        # Broadcast to user-specific topic
        DataSync.broadcast("bookmarks", bookmark.user_id,
          {:created, %{type: :bookmark, bookmark: bookmark}}
        )
        # Broadcast to company-specific topic
        DataSync.broadcast("company_bookmarks", bookmark.company_id,
          {:created, %{type: :bookmark, bookmark: bookmark}}
        )
        result
      error -> error
    end
  end

  @doc """
  Deletes a bookmark.

  Removes a bookmark relationship between a user and a company.
  Broadcasts the deletion event to relevant PubSub topics for real-time updates.

  ## Parameters
    - bookmark: The bookmark struct to delete

  ## Returns
    - `{:ok, bookmark}` on success
    - `{:error, changeset}` on failure
  """
  def delete_bookmark(%Bookmark{} = bookmark) do
    Repo.delete(bookmark)
    |> case do
      {:ok, deleted_bookmark} = result ->
        # Broadcast to user-specific topic
        DataSync.broadcast("bookmarks", deleted_bookmark.user_id,
          {:deleted, %{type: :bookmark, id: deleted_bookmark.id}}
        )
        # Broadcast to company-specific topic
        DataSync.broadcast("company_bookmarks", deleted_bookmark.company_id,
          {:deleted, %{type: :bookmark, id: deleted_bookmark.id}}
        )
        result
      error -> error
    end
  end

  @doc """
  Returns true if the user has bookmarked the company.

  Checks if a bookmark relationship exists between the specified user and company.

  ## Parameters
    - user_id: The ID of the user to check
    - company_id: The ID of the company to check

  ## Returns
    - true if the company is bookmarked by the user
    - false otherwise
  """
  def bookmarked?(user_id, company_id) do
    Bookmark
    |> where(user_id: ^user_id, company_id: ^company_id)
    |> Repo.exists?()
  end

  @doc """
  Returns the count of bookmarks for a user.

  Counts the total number of bookmarks created by a specific user.

  ## Parameters
    - user_id: The ID of the user whose bookmarks to count

  ## Returns
    - Integer count of bookmarks
  """
  def count_user_bookmarks(user_id) do
    Bookmark
    |> where(user_id: ^user_id)
    |> Repo.aggregate(:count, :id)
  end
end
