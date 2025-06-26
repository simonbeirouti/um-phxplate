defmodule Core.Companies.Employee do
  @moduledoc """
  Schema for company employees.

  This schema represents an employee of a company in the system. It stores basic
  employee information such as email, position, department, and salary. Employees
  are associated with both a company and a user profile. The schema enforces
  validation rules for employee data and tracks changes for activity logging.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "employees" do
    field :email, :string
    field :position, :string
    field :department, :string
    field :salary, :decimal

    belongs_to :company, Core.Companies.Company
    belongs_to :profile, Core.Accounts.Profile

    timestamps()
  end

  @doc """
  Changeset function for creating or updating an employee.

  Validates required fields, format constraints, and foreign key constraints.
  Logs employee creation or update activity if an actor is provided.

  ## Parameters
    - employee: The employee struct to change
    - attrs: Map of attributes to apply to the employee
    - actor: (Optional) The user performing the action
  """
  def changeset(employee, attrs, actor \\ nil) do
    changeset = employee
    |> cast(attrs, [:email, :position, :department, :salary, :company_id, :profile_id])
    |> validate_required([:email, :company_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:profile_id)

    if actor do
      action = if employee.id, do: "employee_update", else: "employee_create"
      changes = if employee.id, do: Map.take(attrs, [:position, :department, :salary]), else: %{}
      Core.Tracking.track_employee_activity(action, employee, actor, changes)
    end

    changeset
  end
end
