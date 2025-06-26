defmodule Core.Repo.Migrations.CreateAiUsageLogs do
  use Ecto.Migration

  def change do
    # Create enum for usage status
    execute "CREATE TYPE ai_usage_status AS ENUM ('success', 'error', 'timeout')", ""

    create table(:ai_usage_logs) do
      add :model, :string, null: false
      add :action, :string, null: false  # chat, stream_chat, evaluation, etc.
      add :status, :ai_usage_status, null: false
      add :prompt_tokens, :integer, null: true
      add :completion_tokens, :integer, null: true
      add :total_tokens, :integer, null: true
      add :response_time, :integer, null: true  # in milliseconds
      add :error_message, :text, null: true
      add :metadata, :map, default: %{}

      # Foreign key references
      add :user_id, references(:users, on_delete: :nothing), null: true
      add :conversation_id, references(:ai_conversations, on_delete: :nothing), null: true
      add :message_id, references(:ai_messages, on_delete: :nothing), null: true

      timestamps(type: :utc_datetime)
    end

    # Indexes for efficient querying
    create index(:ai_usage_logs, [:user_id])
    create index(:ai_usage_logs, [:conversation_id])
    create index(:ai_usage_logs, [:message_id])
    create index(:ai_usage_logs, [:model])
    create index(:ai_usage_logs, [:action])
    create index(:ai_usage_logs, [:status])
    create index(:ai_usage_logs, [:inserted_at])
    create index(:ai_usage_logs, [:model, :status])
    create index(:ai_usage_logs, [:model, :inserted_at])
    create index(:ai_usage_logs, [:user_id, :inserted_at])
  end
end
