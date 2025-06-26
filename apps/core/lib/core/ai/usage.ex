defmodule Core.AI.Usage do
  @moduledoc """
  Schema for tracking AI model usage, performance metrics, and success rates.

  This schema tracks every AI model invocation including:
  - Model usage statistics
  - Success/failure rates
  - Token consumption
  - Response times
  - Error tracking
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Core.Repo
  alias Phoenix.PubSub

  schema "ai_usage_logs" do
    field :model, :string
    field :action, :string  # "chat", "stream_chat", "evaluation", "title_generation", etc.
    field :status, :string  # "success", "error", "timeout"
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :total_tokens, :integer
    field :response_time, :integer  # in milliseconds
    field :error_message, :string
    field :metadata, :map

    # Associations
    belongs_to :user, Core.Accounts.User
    belongs_to :conversation, Core.AI.Conversation
    belongs_to :message, Core.AI.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [
      :model, :action, :status, :prompt_tokens, :completion_tokens,
      :total_tokens, :response_time, :error_message, :metadata,
      :user_id, :conversation_id, :message_id
    ])
    |> validate_required([:model, :action, :status])
    |> validate_inclusion(:status, ["success", "error", "timeout"])
    |> validate_number(:prompt_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:completion_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:response_time, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:message_id)
  end

  @doc """
  Creates a usage log entry and broadcasts to PubSub for realtime updates.
  """
  def log_usage(attrs) do
    case %__MODULE__{}
         |> changeset(attrs)
         |> Repo.insert() do
      {:ok, usage_log} ->
        # Broadcast to PubSub for realtime updates
        PubSub.broadcast(
          Core.PubSub,
          "ai_usage",
          {:usage_logged, usage_log}
        )

        # Also broadcast specifically for error tracking if it's an error/timeout
        if usage_log.status in ["error", "timeout"] do
          PubSub.broadcast(
            Core.PubSub,
            "ai_errors",
            {:error_logged, usage_log}
          )
        end

        {:ok, usage_log}

      error ->
        error
    end
  end

  @doc """
  Gets usage statistics for a specific model.
  """
  def get_model_stats(model, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    start_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    from(u in __MODULE__,
      where: u.model == ^model and u.inserted_at >= ^start_date,
      select: %{
        total_requests: count(u.id),
        successful_requests: sum(fragment("CASE WHEN ? = 'success' THEN 1 ELSE 0 END", u.status)),
        error_requests: sum(fragment("CASE WHEN ? = 'error' THEN 1 ELSE 0 END", u.status)),
        total_tokens: sum(u.total_tokens),
        avg_response_time: avg(u.response_time),
        total_prompt_tokens: sum(u.prompt_tokens),
        total_completion_tokens: sum(u.completion_tokens)
      }
    )
    |> Repo.one()
  end

  @doc """
  Gets usage statistics for all models.
  """
  def get_all_models_stats(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    start_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    from(u in __MODULE__,
      where: u.inserted_at >= ^start_date,
      group_by: u.model,
      select: %{
        model: u.model,
        total_requests: count(u.id),
        successful_requests: sum(fragment("CASE WHEN ? = 'success' THEN 1 ELSE 0 END", u.status)),
        error_requests: sum(fragment("CASE WHEN ? = 'error' THEN 1 ELSE 0 END", u.status)),
        total_tokens: sum(u.total_tokens),
        avg_response_time: avg(u.response_time),
        total_prompt_tokens: sum(u.prompt_tokens),
        total_completion_tokens: sum(u.completion_tokens)
      },
      order_by: [desc: count(u.id)]
    )
    |> Repo.all()
  end

  @doc """
  Gets usage timeline data for charts.
  """
  def get_usage_timeline(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    model = Keyword.get(opts, :model)
    start_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query = from(u in __MODULE__,
      where: u.inserted_at >= ^start_date,
      group_by: [fragment("DATE(?)", u.inserted_at), u.model, u.status],
      select: %{
        date: fragment("DATE(?)", u.inserted_at),
        model: u.model,
        status: u.status,
        count: count(u.id),
        total_tokens: sum(u.total_tokens),
        avg_response_time: avg(u.response_time)
      },
      order_by: [asc: fragment("DATE(?)", u.inserted_at)]
    )

    query = if model do
      where(query, [u], u.model == ^model)
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Gets recent error logs for debugging.
  """
  def get_recent_errors(limit \\ 50) do
    from(u in __MODULE__,
      where: u.status == "error",
      order_by: [desc: u.inserted_at],
      limit: ^limit,
      preload: [:user, :conversation, :message]
    )
    |> Repo.all()
  end

  @doc """
  Gets paginated and filtered error logs for debugging.

  ## Options
    * `:page` - Page number (default: 1)
    * `:per_page` - Items per page (default: 20)
    * `:model` - Filter by model display name (default: nil for all models)
    * `:status` - Filter by status (default: "error", can be "error", "timeout", or "all" for all statuses)
    * `:days` - Filter by time range in days (default: 30)

  ## Returns
    Map with keys: :errors, :page, :per_page, :total_count, :total_pages
  """
  def get_errors_paginated(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    model_display_name = Keyword.get(opts, :model)
    status_filter = Keyword.get(opts, :status, "error")
    days = Keyword.get(opts, :days, 30)

    start_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)
    offset = (page - 1) * per_page

    # Build the base query
    query = from(u in __MODULE__,
      where: u.inserted_at >= ^start_date,
      order_by: [desc: u.inserted_at],
      preload: [:user, :conversation, :message]
    )

    # Apply status filter
    query = case status_filter do
      "all" -> where(query, [u], u.status in ["error", "timeout"])
      "error" -> where(query, [u], u.status == "error")
      "timeout" -> where(query, [u], u.status == "timeout")
      _ -> where(query, [u], u.status == ^status_filter)
    end

    # Apply model filter if specified - filter by display name since that's what's stored in DB
    query = if model_display_name && model_display_name != "all" do
      where(query, [u], u.model == ^model_display_name)
    else
      query
    end

    # Get total count for pagination
    total_count = Repo.aggregate(query, :count, :id)
    total_pages = max(1, ceil(total_count / per_page))

    # Get paginated results
    errors = query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    %{
      errors: errors,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @doc """
  Gets usage statistics for all models with optional filtering.

  ## Options
    * `:days` - Filter by time range in days (default: 30)
    * `:status` - Filter by status (default: "all", can be "success", "error", "timeout", or "all")
    * `:model` - Filter by specific model display name (default: nil for all models)
  """
  def get_all_models_stats_filtered(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    status_filter = Keyword.get(opts, :status, "all")
    model_display_name = Keyword.get(opts, :model)

    start_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query = from(u in __MODULE__,
      where: u.inserted_at >= ^start_date,
      group_by: u.model,
      select: %{
        model: u.model,
        total_requests: count(u.id),
        successful_requests: sum(fragment("CASE WHEN ? = 'success' THEN 1 ELSE 0 END", u.status)),
        error_requests: sum(fragment("CASE WHEN ? = 'error' THEN 1 ELSE 0 END", u.status)),
        timeout_requests: sum(fragment("CASE WHEN ? = 'timeout' THEN 1 ELSE 0 END", u.status)),
        total_tokens: sum(u.total_tokens),
        avg_response_time: avg(u.response_time),
        total_prompt_tokens: sum(u.prompt_tokens),
        total_completion_tokens: sum(u.completion_tokens)
      },
      order_by: [desc: count(u.id)]
    )

    # Apply status filter if not "all"
    query = case status_filter do
      "all" -> query
      status -> where(query, [u], u.status == ^status)
    end

    # Apply model filter if specified - filter by display name since that's what's stored in DB
    query = if model_display_name && model_display_name != "all" do
      where(query, [u], u.model == ^model_display_name)
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Gets user usage statistics.
  """
  def get_user_stats(user_id, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    start_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    from(u in __MODULE__,
      where: u.user_id == ^user_id and u.inserted_at >= ^start_date,
      group_by: u.model,
      select: %{
        model: u.model,
        total_requests: count(u.id),
        successful_requests: sum(fragment("CASE WHEN ? = 'success' THEN 1 ELSE 0 END", u.status)),
        total_tokens: sum(u.total_tokens),
        avg_response_time: avg(u.response_time)
      },
      order_by: [desc: count(u.id)]
    )
    |> Repo.all()
  end
end
