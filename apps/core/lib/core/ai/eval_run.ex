defmodule Core.AI.EvalRun do
  @moduledoc """
  Schema for AI evaluation runs.

  This schema represents individual runs of evaluations, tracking the results
  and performance metrics when an evaluation is executed against a specific
  model and prompt combination.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Core.Accounts.User
  alias Core.AI.{Eval, Prompt}

  @statuses ["pending", "running", "completed", "failed"]

  schema "ai_eval_runs" do
    field :model, :string
    field :results, :map, default: %{}
    field :score, :float
    field :status, :string, default: "pending"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    # Advanced AI parameters used for this evaluation run
    field :max_tokens, :integer
    field :max_tokens_active, :boolean, default: false
    field :temperature, :float
    field :temperature_active, :boolean, default: false
    field :top_k, :integer
    field :top_k_active, :boolean, default: false
    field :top_p, :float
    field :top_p_active, :boolean, default: false

    belongs_to :eval, Eval
    belongs_to :prompt, Prompt
    belongs_to :run_by_user, User, foreign_key: :run_by

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an eval run.
  """
  def changeset(eval_run, attrs) do
    eval_run
    |> cast(attrs, [
      :eval_id, :prompt_id, :model, :results, :score, :status, :started_at, :completed_at, :run_by,
      :max_tokens, :max_tokens_active, :temperature, :temperature_active,
      :top_k, :top_k_active, :top_p, :top_p_active
    ])
    |> validate_required([:eval_id, :model])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 5.0)
    |> validate_number(:max_tokens, greater_than: 0)
    |> validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:top_k, greater_than: 0)
    |> validate_number(:top_p, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:eval_id)
    |> foreign_key_constraint(:prompt_id)
    |> foreign_key_constraint(:run_by)
  end

  @doc """
  Returns the list of available statuses.
  """
  def statuses, do: @statuses

  @doc """
  Changeset for starting an eval run.
  """
  def start_changeset(eval_run) do
    eval_run
    |> cast(%{status: "running", started_at: DateTime.utc_now()}, [:status, :started_at])
    |> validate_required([:status, :started_at])
  end

  @doc """
  Changeset for completing an eval run.
  """
  def complete_changeset(eval_run, results, score) do
    eval_run
    |> cast(%{
      status: "completed",
      completed_at: DateTime.utc_now(),
      results: results,
      score: score
    }, [:status, :completed_at, :results, :score])
    |> validate_required([:status, :completed_at, :results])
  end

  @doc """
  Changeset for failing an eval run.
  """
  def fail_changeset(eval_run, error_message) do
    eval_run
    |> cast(%{
      status: "failed",
      completed_at: DateTime.utc_now(),
      results: %{error: error_message}
    }, [:status, :completed_at, :results])
    |> validate_required([:status, :completed_at, :results])
  end
end
