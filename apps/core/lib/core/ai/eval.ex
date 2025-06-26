defmodule Core.AI.Eval do
  @moduledoc """
  Schema for AI evaluations.

  This schema represents evaluation tests that can be run against AI models
  to measure their performance on specific tasks or criteria.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Core.Accounts.User
  alias Core.AI.EvalRun

  schema "ai_evals" do
    field :name, :string
    field :description, :string
    field :test_cases, :map, default: %{}
    field :expected_outputs, :map, default: %{}
    field :evaluation_criteria, :string
    field :is_active, :boolean, default: true

    belongs_to :created_by_user, User, foreign_key: :created_by
    has_many :eval_runs, EvalRun

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an eval.
  """
  def changeset(eval, attrs) do
    eval
    |> cast(attrs, [:name, :description, :test_cases, :expected_outputs, :evaluation_criteria, :is_active, :created_by])
    |> validate_required([:name, :test_cases, :evaluation_criteria])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:evaluation_criteria, min: 1)
    |> unique_constraint(:name)
    |> validate_test_cases()
  end

  defp validate_test_cases(changeset) do
    case get_field(changeset, :test_cases) do
      test_cases when is_map(test_cases) and map_size(test_cases) > 0 ->
        changeset
      _ ->
        add_error(changeset, :test_cases, "must contain at least one test case")
    end
  end
end
