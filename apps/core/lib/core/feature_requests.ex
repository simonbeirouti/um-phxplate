defmodule Core.FeatureRequests do
  @moduledoc """
  The FeatureRequests context.

  This context handles the creation and management of feature requests
  submitted by users. It also broadcasts changes to feature requests via PubSub
  for real-time updates across the application.
  """

  import Ecto.Query, warn: false
  alias Core.Repo
  alias Core.FeatureRequests.FeatureRequest
  alias Core.PubSub.DataSync

  @doc """
  Returns the list of feature_requests.

  ## Options
    * `:page` - The page number to fetch (default: 1)
    * `:per_page` - The number of items per page (default: 10)
    * `:request_type` - Filter by request type: `:feature` (1) or `:feedback` (2), or `:all` for both

  ## Examples

      iex> list_feature_requests()
      [%FeatureRequest{}, ...]

      iex> list_feature_requests(page: 2, per_page: 20, request_type: :feature)
      [%FeatureRequest{}, ...]

  """
  def list_feature_requests(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)
    request_type = Keyword.get(opts, :request_type, :all)

    offset = (page - 1) * per_page

    FeatureRequest
    |> filter_by_request_type(request_type)
    |> order_by([f], desc: f.inserted_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns the total count of feature requests, optionally filtered by request type.

  ## Options
    * `:request_type` - Filter by request type: `:feature` (1) or `:feedback` (2), or `:all` for both

  ## Examples

      iex> count_feature_requests()
      42

      iex> count_feature_requests(request_type: :feature)
      24

  """
  def count_feature_requests(opts \\ []) do
    request_type = Keyword.get(opts, :request_type, :all)

    FeatureRequest
    |> filter_by_request_type(request_type)
    |> Repo.aggregate(:count)
  end

  # Helper function to filter by request type
  defp filter_by_request_type(query, :all), do: query
  defp filter_by_request_type(query, :feature), do: where(query, [f], f.feasibility_rating == 1)
  defp filter_by_request_type(query, :feedback), do: where(query, [f], f.feasibility_rating == 2)

  @doc """
  Gets a single feature_request.

  Raises `Ecto.NoResultsError` if the Feature request does not exist.

  ## Examples

      iex> get_feature_request!(123)
      %FeatureRequest{}

      iex> get_feature_request!(456)
      ** (Ecto.NoResultsError)

  """
  def get_feature_request!(id), do: Repo.get!(FeatureRequest, id)

  @doc """
  Creates a feature_request.

  ## Examples

      iex> create_feature_request(%{field: value})
      {:ok, %FeatureRequest{}}

      iex> create_feature_request(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_feature_request(attrs \\  %{}) do
    result = %FeatureRequest{}
    |> FeatureRequest.changeset(attrs)
    |> Repo.insert()

    # Broadcast the creation event if successful
    case result do
      {:ok, feature_request} ->
        DataSync.broadcast("feature_requests", "all", {:created, feature_request})
      _ -> :ok
    end

    result
  end

  @doc """
  Updates a feature_request.

  ## Examples

      iex> update_feature_request(feature_request, %{field: new_value})
      {:ok, %FeatureRequest{}}

      iex> update_feature_request(feature_request, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_feature_request(%FeatureRequest{} = feature_request, attrs) do
    result = feature_request
    |> FeatureRequest.changeset(attrs)
    |> Repo.update()

    # Broadcast the update event if successful
    case result do
      {:ok, updated_feature_request} ->
        DataSync.broadcast("feature_requests", "all", {:updated, updated_feature_request})
      _ -> :ok
    end

    result
  end

  @doc """
  Deletes a feature_request.

  ## Examples

      iex> delete_feature_request(feature_request)
      {:ok, %FeatureRequest{}}

      iex> delete_feature_request(feature_request)
      {:error, %Ecto.Changeset{}}

  """
  def delete_feature_request(%FeatureRequest{} = feature_request) do
    result = Repo.delete(feature_request)

    # Broadcast the deletion event if successful
    case result do
      {:ok, deleted_feature_request} ->
        DataSync.broadcast("feature_requests", "all", {:deleted, deleted_feature_request.id})
      _ -> :ok
    end

    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking feature_request changes.

  ## Examples

      iex> change_feature_request(feature_request)
      %Ecto.Changeset{data: %FeatureRequest{}}

  """
  def change_feature_request(%FeatureRequest{} = feature_request, attrs \\ %{}) do
    FeatureRequest.changeset(feature_request, attrs)
  end
end
