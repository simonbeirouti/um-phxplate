defmodule Core.Repo.Migrations.CreateAiEvalsAndPrompts do
  use Ecto.Migration

  def change do
    # Create AI prompts table
    create table(:ai_prompts) do
      add :name, :string, null: false
      add :description, :text
      add :content, :text, null: false
      add :category, :string, default: "general"
      add :is_active, :boolean, default: true, null: false
      add :created_by, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # Create AI evals table
    create table(:ai_evals) do
      add :name, :string, null: false
      add :description, :text
      add :test_cases, :map, default: %{}
      add :expected_outputs, :map, default: %{}
      add :evaluation_criteria, :text
      add :is_active, :boolean, default: true, null: false
      add :created_by, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # Create AI eval runs table for tracking evaluation results
    create table(:ai_eval_runs) do
      add :eval_id, references(:ai_evals, on_delete: :delete_all), null: false
      add :prompt_id, references(:ai_prompts, on_delete: :nilify_all)
      add :model, :string, null: false
      add :results, :map, default: %{}
      add :score, :float
      add :status, :string, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :run_by, references(:users, on_delete: :nilify_all)

      # Advanced AI parameters used for this evaluation run
      add :max_tokens, :integer, null: true
      add :max_tokens_active, :boolean, default: false, null: false
      add :temperature, :float, null: true
      add :temperature_active, :boolean, default: false, null: false
      add :top_k, :integer, null: true
      add :top_k_active, :boolean, default: false, null: false
      add :top_p, :float, null: true
      add :top_p_active, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    # Create indexes
    create index(:ai_prompts, [:name])
    create index(:ai_prompts, [:category])
    create index(:ai_prompts, [:is_active])
    create index(:ai_prompts, [:created_by])
    create index(:ai_prompts, [:inserted_at])

    create index(:ai_evals, [:name])
    create index(:ai_evals, [:is_active])
    create index(:ai_evals, [:created_by])
    create index(:ai_evals, [:inserted_at])

    create index(:ai_eval_runs, [:eval_id])
    create index(:ai_eval_runs, [:prompt_id])
    create index(:ai_eval_runs, [:model])
    create index(:ai_eval_runs, [:status])
    create index(:ai_eval_runs, [:run_by])
    create index(:ai_eval_runs, [:inserted_at])
  end
end
