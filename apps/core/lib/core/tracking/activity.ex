defmodule Core.Tracking.Activity do
  @moduledoc """
  Schema for activity tracking.

  This schema represents an activity record in the system, used for audit logging
  and tracking changes made by users. It stores information about actions performed,
  the affected entity, changes made, and metadata. Activities are associated with
  both the actor (user performing the action) and optionally a company context.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "activities" do
    field :action, :string
    field :entity_type, :string
    field :entity_id, :integer
    field :changes, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :actor, Core.Accounts.User
    belongs_to :company, Core.Companies.Company

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset function for creating or updating an activity.

  Validates required fields for basic activity tracking.

  ## Parameters
    - activity: The activity struct to change
    - attrs: Map of attributes to apply to the activity
  """
  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:action, :entity_type, :entity_id, :changes, :metadata, :actor_id, :company_id])
    |> validate_required([:action, :entity_type, :entity_id])
  end

  @doc """
  Creates a new activity record.

  Takes a map of activity attributes and persists it to the database.

  ## Parameters
    - attrs: Map of attributes for the activity

  ## Returns
    - `{:ok, activity}` on success
    - `{:error, changeset}` on validation failure
  """
  def track(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Core.Repo.insert()
  end

  @doc """
  Gets activities for a specific entity.

  Retrieves the most recent activities related to a specific entity,
  ordered by insertion date with newest first.

  ## Parameters
    - entity_type: The type of entity (e.g., "user", "company", "employee")
    - entity_id: The ID of the entity
    - limit: Maximum number of activities to retrieve (default: 10)

  ## Returns
    - List of activity records with their associated actors
  """
  def get_entity_activities(entity_type, entity_id, limit \\ 10) do
    from(a in __MODULE__,
      where: a.entity_type == ^entity_type and a.entity_id == ^entity_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit,
      preload: [:actor]
    )
    |> Core.Repo.all()
  end

  @doc """
  Gets activities for a company.

  Retrieves the most recent activities performed in the context of a specific company,
  ordered by insertion date with newest first.

  ## Parameters
    - company_id: The ID of the company
    - limit: Maximum number of activities to retrieve (default: 10)

  ## Returns
    - List of activity records with their associated actors
  """
  def get_company_activities(company_id, limit \\ 10) do
    from(a in __MODULE__,
      where: a.company_id == ^company_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit,
      preload: [:actor]
    )
    |> Core.Repo.all()
  end
end
