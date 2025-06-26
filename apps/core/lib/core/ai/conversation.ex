defmodule Core.AI.Conversation do
  @moduledoc """
  Schema for AI chat conversations.

  This schema represents a conversation between a user and the AI assistant.
  Each conversation has a title, belongs to a user, and contains multiple messages.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Core.Accounts.User
  alias Core.AI.Message
  alias Core.AI.Prompt

  schema "ai_conversations" do
    field :title, :string
    field :system_prompt, :string
    field :archived, :boolean, default: false

    # Selected prompt for the conversation
    belongs_to :selected_prompt, Prompt

    # Advanced AI parameters for the conversation
    field :max_tokens, :integer
    field :max_tokens_active, :boolean, default: false
    field :temperature, :float
    field :temperature_active, :boolean, default: false
    field :top_k, :integer
    field :top_k_active, :boolean, default: false
    field :top_p, :float
    field :top_p_active, :boolean, default: false

    belongs_to :user, User
    has_many :messages, Message, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a conversation.
  """
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [
      :title, :system_prompt, :archived, :user_id,
      :selected_prompt_id,
      :max_tokens, :max_tokens_active, :temperature, :temperature_active,
      :top_k, :top_k_active, :top_p, :top_p_active
    ])
    |> validate_required([:title, :user_id])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_number(:max_tokens, greater_than: 0, less_than_or_equal_to: 4096)
    |> validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:top_k, greater_than: 0, less_than_or_equal_to: 5)
    |> validate_number(:top_p, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating just the title.
  """
  def title_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
  end

  @doc """
  Changeset for archiving/unarchiving a conversation.
  """
  def archive_changeset(conversation, archived) do
    conversation
    |> cast(%{archived: archived}, [:archived])
    |> validate_required([:archived])
  end

  @doc """
  Changeset for updating advanced AI parameters.
  """
  def advanced_params_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [
      :max_tokens, :max_tokens_active, :temperature, :temperature_active,
      :top_k, :top_k_active, :top_p, :top_p_active
    ])
    |> validate_number(:max_tokens, greater_than: 0, less_than_or_equal_to: 4096)
    |> validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:top_k, greater_than: 0, less_than_or_equal_to: 5)
    |> validate_number(:top_p, greater_than: 0.0, less_than_or_equal_to: 1.0)
  end

  @doc """
  Changeset for updating prompt settings.
  """
  def prompt_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:selected_prompt_id])
    |> foreign_key_constraint(:selected_prompt_id)
  end
end
