defmodule Core.AI.Message do
  @moduledoc """
  Schema for AI chat messages.

  This schema represents individual messages within an AI conversation.
  Messages can be from either the user or the assistant.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Core.AI.Conversation
  alias Core.AI.Prompt

  @roles [:user, :assistant, :system]

  schema "ai_messages" do
    field :role, Ecto.Enum, values: @roles
    field :content, :string
    field :model, :string
    field :metadata, :map, default: %{}

    # Prompt used for this specific message
    belongs_to :prompt, Prompt

    # Advanced AI parameters used for this specific message (for performance tracking)
    field :max_tokens, :integer
    field :temperature, :float
    field :top_k, :integer
    field :top_p, :float

    belongs_to :conversation, Conversation

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a message.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :role, :content, :model, :metadata, :conversation_id,
      :prompt_id,
      :max_tokens, :temperature, :top_k, :top_p
    ])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, @roles)
    |> validate_length(:content, min: 1)
    |> validate_number(:max_tokens, greater_than: 0, less_than_or_equal_to: 4096)
    |> validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:top_k, greater_than: 0, less_than_or_equal_to: 5)
    |> validate_number(:top_p, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:prompt_id)
  end
end
