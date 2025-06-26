defmodule Core.AI.Prompt do
  @moduledoc """
  Schema for AI prompts.

  This schema represents reusable prompts that can be used in AI conversations
  and evaluations. Prompts can be categorized and managed through the platform.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Core.Accounts.User

  @categories ["system", "general", "customer_support", "content_generation", "analysis"]

  schema "ai_prompts" do
    field :name, :string
    field :description, :string
    field :content, :string
    field :category, :string, default: "general"
    field :is_active, :boolean, default: true

    belongs_to :created_by_user, User, foreign_key: :created_by

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a prompt.
  """
  def changeset(prompt, attrs) do
    prompt
    |> cast(attrs, [:name, :description, :content, :category, :is_active, :created_by])
    |> validate_required([:name, :content])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:content, min: 1)
    |> validate_inclusion(:category, @categories)
    |> unique_constraint(:name)
  end

  @doc """
  Returns the list of available categories.
  """
  def categories, do: @categories

  @doc """
  Returns a formatted category name for display.
  """
  def format_category(category) do
    category
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
