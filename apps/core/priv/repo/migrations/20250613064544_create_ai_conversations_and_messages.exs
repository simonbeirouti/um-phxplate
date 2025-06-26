defmodule Core.Repo.Migrations.CreateAiConversationsAndMessages do
  use Ecto.Migration

  def change do
    # Create enum for message roles
    execute "CREATE TYPE ai_message_role AS ENUM ('user', 'assistant', 'system')", ""

    create table(:ai_conversations) do
      add :title, :string, null: false
      add :system_prompt, :text
      add :archived, :boolean, default: false, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Selected prompt for the conversation (will be added as foreign key in later migration)
      add :selected_prompt_id, references(:ai_prompts, on_delete: :nilify_all), from: :integer

      # Advanced AI parameters for the conversation
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

    create table(:ai_messages) do
      add :role, :ai_message_role, null: false
      add :content, :text, null: false
      add :model, :string, null: true
      add :metadata, :map, default: %{}
      add :conversation_id, references(:ai_conversations, on_delete: :delete_all), null: false

      # Prompt used for this specific message (will be added as foreign key in later migration)
      add :prompt_id, references(:ai_prompts, on_delete: :nilify_all), from: :integer

      # Advanced AI parameters used for this specific message (for performance tracking)
      add :max_tokens, :integer, null: true
      add :temperature, :float, null: true
      add :top_k, :integer, null: true
      add :top_p, :float, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:ai_conversations, [:user_id])
    create index(:ai_conversations, [:archived])
    create index(:ai_conversations, [:inserted_at])
    create index(:ai_conversations, [:selected_prompt_id])
    create index(:ai_messages, [:prompt_id])
    create index(:ai_messages, [:conversation_id])
    create index(:ai_messages, [:model])
    create index(:ai_messages, [:inserted_at])
  end
end
