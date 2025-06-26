defmodule Core.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    create table(:chat_sessions) do
      add :status, :string, null: false, default: "active"
      add :user_id, references(:users, on_delete: :nilify_all)
      add :anonymous_name, :string
      add :anonymous_email, :string
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :device_os, :string
      add :device_browser, :string
      add :device_type, :string
      add :user_agent, :text
      add :screen_resolution, :string
      add :timezone, :string
      add :language, :string
      add :ip_address, :string

      timestamps()
    end

    create table(:chat_messages) do
      add :content, :text, null: false
      add :sender_type, :string, null: false
      add :chat_session_id, references(:chat_sessions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:chat_sessions, [:user_id])
    create index(:chat_sessions, [:status])
    create index(:chat_messages, [:chat_session_id])
    create index(:chat_messages, [:user_id])
    create index(:chat_sessions, [:device_os])
    create index(:chat_sessions, [:device_browser])
    create index(:chat_sessions, [:device_type])
    create index(:chat_sessions, [:ip_address])
  end
end
