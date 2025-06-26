defmodule Core.Chat.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Core.Repo
  alias Core.Accounts.User
  alias Core.Chat.ChatSession

  schema "chat_messages" do
    field :content, :string
    field :sender_type, :string  # "user" or "admin"

    belongs_to :chat_session, ChatSession
    belongs_to :user, User

    timestamps()
  end

  @doc """
  Creates a changeset for a chat message.
  """
  def changeset(chat_message, attrs) do
    chat_message
    |> cast(attrs, [:content, :sender_type, :chat_session_id, :user_id])
    |> validate_required([:content, :sender_type, :chat_session_id])
    |> validate_inclusion(:sender_type, ["user", "admin"])
  end

  @doc """
  Creates a new chat message.
  """
  def create_message(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a chat message by ID.
  """
  def get_message(id), do: Repo.get(__MODULE__, id)

  @doc """
  Gets all messages for a specific chat session.
  """
  def get_messages_for_session(session_id) do
    __MODULE__
    |> where([m], m.chat_session_id == ^session_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets the most recent message for a chat session.
  """
  def get_latest_message(session_id) do
    __MODULE__
    |> where([m], m.chat_session_id == ^session_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
