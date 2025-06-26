defmodule Core.Companies.Company do
  @moduledoc """
  Schema for companies.

  This schema represents a company in the system, storing basic information like
  name, description, contact details, and subscription plan level. Companies are
  owned by admin users and can have multiple employees. The schema establishes
  these associations and enforces validation rules for company data.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Core.Accounts.User

  schema "companies" do
    field :name, :string
    field :description, :string
    field :address, :string
    field :phone, :string
    field :email, :string
    field :logo, :string
    field :website, :string

    has_many :employees, Core.Companies.Employee
    belongs_to :owner, User

    timestamps()
  end

  @doc """
  Changeset function for creating or updating a company.

  Validates required fields, format constraints, and uniqueness constraints.
  Ensures that the owner is an admin user.

  ## Parameters
    - company: The company struct to change
    - attrs: Map of attributes to apply to the company
    - actor: (Optional) The user performing the action
  """
  def changeset(company, attrs, _actor \\ nil) do
    company
    |> cast(attrs, [:name, :description, :address, :phone, :email, :logo, :website, :owner_id])
    |> validate_required([:name, :owner_id])
    |> validate_owner()
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> unique_constraint(:email)
  end

  @doc """
  Validates that the owner is an admin user.

  Adds an error to the changeset if the owner is not an admin.
  """
  def validate_owner(changeset) do
    case get_field(changeset, :owner_id) do
      nil -> changeset
      owner_id ->
        case Core.Repo.get(User, owner_id) do
          %User{role: :admin} -> changeset
          _ -> add_error(changeset, :owner_id, "must be an admin user")
        end
    end
  end
end
