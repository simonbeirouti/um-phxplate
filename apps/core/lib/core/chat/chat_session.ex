defmodule Core.Chat.ChatSession do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Core.Repo
  alias Core.Accounts.User
  alias Core.Chat.ChatMessage

  schema "chat_sessions" do
    field :status, :string, default: "active"
    field :anonymous_name, :string
    field :anonymous_email, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    # Device information fields
    field :device_os, :string
    field :device_browser, :string
    field :device_type, :string
    field :user_agent, :string
    field :screen_resolution, :string
    field :timezone, :string
    field :language, :string
    field :ip_address, :string

    belongs_to :user, User
    has_many :messages, ChatMessage

    timestamps()
  end

  @doc """
  Creates a changeset for a chat session.
  """
  def changeset(chat_session, attrs) do
    chat_session
    |> cast(attrs, [
      :status, :user_id, :anonymous_name, :anonymous_email, :started_at, :ended_at,
      :device_os, :device_browser, :device_type, :user_agent, :screen_resolution,
      :timezone, :language, :ip_address
    ])
    |> validate_required([:status, :started_at])
    |> validate_user_or_anonymous()
  end

  # Validates that either a user_id or anonymous information is provided.
  defp validate_user_or_anonymous(changeset) do
    user_id = get_field(changeset, :user_id)
    anonymous_name = get_field(changeset, :anonymous_name)
    anonymous_email = get_field(changeset, :anonymous_email)

    if is_nil(user_id) && (is_nil(anonymous_name) || is_nil(anonymous_email)) do
      add_error(changeset, :user_id, "Either user_id or anonymous information must be provided")
    else
      changeset
    end
  end

  @doc """
  Creates a new chat session.
  """
  def create_session(attrs) do
    attrs = Map.put_new(attrs, :started_at, DateTime.utc_now())

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a chat session by ID.
  """
  def get_session(id), do: Repo.get(__MODULE__, id)

  @doc """
  Gets a chat session by ID with preloaded messages.
  """
  def get_session_with_messages(id) do
    __MODULE__
    |> Repo.get(id)
    |> Repo.preload(messages: from(m in ChatMessage, order_by: [asc: m.inserted_at]))
  end

  @doc """
  Lists all active chat sessions.
  """
  def list_active_sessions do
    __MODULE__
    |> where([s], s.status == "active")
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Closes a chat session by setting its status to "closed" and recording the end time.
  """
  def close_session(session) do
    session
    |> changeset(%{status: "closed", ended_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Gets all chat sessions for a specific user.
  """
  def get_sessions_for_user(user_id) do
    __MODULE__
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets all chat sessions for an anonymous user by email.
  """
  def get_sessions_for_anonymous(email) do
    __MODULE__
    |> where([s], s.anonymous_email == ^email)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
    |> Repo.preload(messages: from(m in ChatMessage, order_by: [asc: m.inserted_at]))
  end

  @doc """
  Lists chat sessions with pagination and optional status filtering.

  ## Parameters

    * `page` - The page number (starting from 1)
    * `per_page` - Number of items per page
    * `opts` - Additional options
      * `:status` - Filter by status ("active" or "closed")
  """
  def list_sessions(page, per_page, opts \\ []) do
    status = Keyword.get(opts, :status)
    offset = (page - 1) * per_page

    query = __MODULE__

    query = if status do
      where(query, [s], s.status == ^status)
    else
      query
    end

    query
    |> order_by([s], desc: s.inserted_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Returns the total count of chat sessions.
  """
  def count_sessions do
    Repo.aggregate(__MODULE__, :count, :id)
  end

  @doc """
  Returns the total count of chat sessions with optional filtering by status.

  ## Options

    * `:status` - Filter sessions by status ("active" or "closed")
  """
  def count_sessions(opts) do
    status = Keyword.get(opts, :status)

    query = __MODULE__

    query = if status do
      where(query, [s], s.status == ^status)
    else
      query
    end

    Repo.aggregate(query, :count, :id)
  end
end
