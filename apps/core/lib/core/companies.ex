defmodule Core.Companies do
  @moduledoc """
  The Companies context.

  This context handles all company-related operations including company management,
  employee management, and company invitations. It provides functions for CRUD operations
  on companies and employees, as well as managing the invitation flow for adding new
  employees to companies. It also handles data synchronization through PubSub broadcasts.
  """
  import Ecto.Query, warn: false
  alias Core.Repo
  alias Core.Companies.Company
  alias Core.Companies.Employee
  alias Core.Companies.Invitation
  alias Core.PubSub.DataSync
  alias Core.EndpointHelper

  @doc """
  Returns a list of all companies with their associations preloaded.

  Preloads owner and employees with their profiles.

  ## Options
    - Any options passed are reserved for future use
  """
  def list_companies(_opts \\ []) do
    Company
    |> preload([:owner, employees: [:profile]])
    |> Repo.all()
  end

  @doc """
  Returns a list of companies owned by a specific user.

  ## Parameters
    - user_id: The ID of the user who owns the companies

  ## Options
    - Any options passed are reserved for future use
  """
  def list_companies_by_owner(user_id, _opts \\ []) do
    Company
    |> where(owner_id: ^user_id)
    |> preload([:owner, employees: [:profile]])
    |> Repo.all()
  end

  @doc """
  Gets a single company by ID with employees preloaded.

  Returns nil if the company doesn't exist.

  ## Parameters
    - id: The ID of the company to retrieve
  """
  def get_company(id) do
    Company
    |> where(id: ^id)
    |> preload([employees: [:profile]])
    |> Repo.one()
  end

  @doc """
  Gets a single company by ID with employees preloaded.

  Raises Ecto.NoResultsError if the company doesn't exist.

  ## Parameters
    - id: The ID of the company to retrieve
  """
  def get_company!(id) do
    Company
    |> where(id: ^id)
    |> preload([employees: [:profile]])
    |> Repo.one!()
  end

  @doc """
  Creates a company with the given attributes.

  Also handles tracking the activity and broadcasting the creation event.

  ## Parameters
    - attrs: Map of attributes for creating the company

  ## Examples

      iex> create_company(%{name: "ACME Corp", owner_id: 1})
      {:ok, %Company{}}

      iex> create_company(%{name: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_company(attrs \\ %{}) do
    %Company{}
    |> Company.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, company} ->
        # Preload all necessary associations
        company = Repo.preload(company, [:owner, employees: [:profile]])
        # Track activity
        Core.Tracking.track_company_activity("company_create", company, company.owner)
        # Broadcast creation
        DataSync.broadcast("companies", company.id, {:created, %{type: :company, company: company}})
        DataSync.broadcast("companies", "all", {:created, %{type: :company, company: company}})
        {:ok, company}
      error -> error
    end
  end

  @doc """
  Updates a company with the given attributes.

  Also handles tracking changed fields and broadcasting the update event.

  ## Parameters
    - company: The company struct to update
    - attrs: Map of attributes to update
    - actor: The user performing the update (defaults to company owner if nil)

  ## Examples

      iex> update_company(company, %{name: "Updated Corp"})
      {:ok, %Company{}}

      iex> update_company(company, %{name: ""})
      {:error, %Ecto.Changeset{}}
  """
  def update_company(%Company{} = company, attrs, actor \\ nil) do
    company
    |> Company.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_company} = result ->
        # Track changed fields
        changed_fields = Enum.reduce(["name", "description", "address", "phone", "email", "plan", "logo", "website"], %{}, fn field, acc ->
          old_value = Map.get(company, String.to_atom(field))
          new_value = Map.get(attrs, field)
          if new_value && old_value != new_value do
            Map.put(acc, field, new_value)
          else
            acc
          end
        end)

        if map_size(changed_fields) > 0 do
          Core.Tracking.track_company_activity("company_update", updated_company, actor || updated_company.owner, changed_fields)
        end

        # Broadcast update
        DataSync.broadcast("companies", company.id, {:updated, %{type: :company, company: updated_company}})
        DataSync.broadcast("companies", "all", {:updated, %{type: :company, company: updated_company}})
        result
      error -> error
    end
  end

  @doc """
  Deletes a company.

  Also broadcasts the deletion event.

  ## Parameters
    - company: The company struct to delete

  ## Examples

      iex> delete_company(company)
      {:ok, %Company{}}
  """
  def delete_company(%Company{} = company) do
    Repo.delete(company)
    |> case do
      {:ok, deleted_company} = result ->
        # Broadcast deletion
        DataSync.broadcast("companies", deleted_company.id, {:deleted, %{type: :company, id: deleted_company.id}})
        DataSync.broadcast("companies", "all", {:deleted, %{type: :company, id: deleted_company.id}})
        result
      error -> error
    end
  end

  @doc """
  Returns a list of all employees.
  """
  def list_employees do
    Repo.all(Employee)
  end

  @doc """
  Gets a single employee by ID.

  Raises Ecto.NoResultsError if the employee doesn't exist.

  ## Parameters
    - id: The ID of the employee to retrieve
  """
  def get_employee!(id), do: Repo.get!(Employee, id)

  @doc """
  Creates an employee with the given attributes.

  Also broadcasts the creation event.

  ## Parameters
    - attrs: Map of attributes for creating the employee

  ## Examples

      iex> create_employee(%{email: "user@example.com", company_id: 1})
      {:ok, %Employee{}}

      iex> create_employee(%{email: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_employee(attrs \\ %{}) do
    %Employee{}
    |> Employee.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, employee} = result ->
        # Broadcast employee creation
        DataSync.broadcast("employees", employee.company_id, {:created, %{type: :employee, employee: employee}})
        DataSync.broadcast("employees", "all", {:created, %{type: :employee, employee: employee, global_scope: true}})
        result
      error -> error
    end
  end

  @doc """
  Updates an employee with the given attributes.

  Also broadcasts the update event.

  ## Parameters
    - employee: The employee struct to update
    - attrs: Map of attributes to update

  ## Examples

      iex> update_employee(employee, %{position: "Manager"})
      {:ok, %Employee{}}

      iex> update_employee(employee, %{email: ""})
      {:error, %Ecto.Changeset{}}
  """
  def update_employee(%Employee{} = employee, attrs) do
    employee
    |> Employee.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_employee} = result ->
        # Broadcast employee update
        DataSync.broadcast("employees", updated_employee.company_id,
          {:updated, %{type: :employee, employee: updated_employee}}
        )
        result
      error -> error
    end
  end

  @doc """
  Deletes an employee.

  Also tracks the activity and broadcasts the deletion event.

  ## Parameters
    - employee: The employee struct to delete
    - actor: The user performing the deletion (optional)

  ## Examples

      iex> delete_employee(employee)
      {:ok, %Employee{}}
  """
  def delete_employee(%Employee{} = employee, actor \\ nil) do
    # Preload the employee with its profile before deletion
    employee = Repo.preload(employee, [:profile])

    case Repo.delete(employee) do
      {:ok, deleted_employee} = result ->
        if actor do
          Core.Tracking.track_company_activity(
            "employee_delete",
            %{id: deleted_employee.company_id},
            actor,
            %{"employee_email" => deleted_employee.email}
          )
        end
        # Broadcast employee deletion with full employee data
        DataSync.broadcast("employees", deleted_employee.company_id,
          {:deleted, %{type: :employee, employee: deleted_employee}}
        )
        # Also broadcast to the all topic
        DataSync.broadcast("employees", "all",
          {:deleted, %{type: :employee, employee: deleted_employee, global_scope: true}}
        )
        result
      error -> error
    end
  end

  @doc """
  Gets all employees for a specific company.

  ## Parameters
    - company: The company struct whose employees to retrieve
  """
  def get_company_employees(%Company{} = company) do
    company
    |> Ecto.assoc(:employees)
    |> preload(:profile)
    |> Repo.all()
  end

  @doc """
  Returns the total number of companies in the system.
  """
  def count_companies do
    Repo.aggregate(Company, :count, :id)
  end

  @doc """
  Returns the total number of employees in the system.
  """
  def count_employees do
    Repo.aggregate(Employee, :count, :id)
  end

  @doc """
  Sends an invitation to join a company.

  Creates or replaces an invitation record, sends an email invitation,
  tracks the activity, and broadcasts the invitation events.

  ## Parameters
    - company: The company struct
    - email: The email address to send the invitation to
    - inviter: The user sending the invitation

  ## Returns
    - `{:ok, invitation}` on success
    - `{:error, changeset}` on validation failure
    - Other error tuples on other failures
  """
  def invite_to_company(%Company{} = company, email, inviter) do
    token = EndpointHelper.sign_token(:invitation, "company_invitation", %{
      company_id: company.id,
      email: email
    })

    invitation_attrs = %{
      email: email,
      token: token,
      company_id: company.id,
      inviter_id: inviter.id
    }

    # First check for and delete any existing invitations
    existing_invitation = Repo.get_by(Invitation, email: email, company_id: company.id)

    if existing_invitation do
      # Delete existing invitation and broadcast deletion
      Repo.delete(existing_invitation)
      DataSync.broadcast("invitations", company.id,
        {:deleted, %{type: :invitation, id: existing_invitation.id}}
      )
      DataSync.broadcast("user_invitations", email,
        {:deleted, %{type: :invitation, id: existing_invitation.id}}
      )
    end

    # Create the new invitation record
    with {:ok, invitation} <- create_invitation(invitation_attrs),
         invitation = Repo.preload(invitation, [:company, :inviter]),
         invitation_url = EndpointHelper.invitation_url() <> "/dashboard/invites/#{token}",
         {:ok, _email} <- Core.Accounts.UserNotifier.deliver_company_invitation(email, company, invitation_url) do
      # Track the invitation activity
      Core.Tracking.track_company_activity(
        "employee_invite",
        company,
        inviter,
        %{"invited_email" => email}
      )
      # Broadcast invitation creation
      DataSync.broadcast("invitations", company.id, {:created, %{type: :invitation, invitation: invitation}})
      DataSync.broadcast("user_invitations", email, {:created, %{type: :invitation, invitation: invitation}})
      {:ok, invitation}
    else
      {:error, changeset} -> {:error, changeset}
      error -> error
    end
  end

  @doc """
  Creates a company invitation.

  ## Parameters
    - attrs: Map of attributes for creating the invitation

  ## Returns
    - `{:ok, invitation}` on success
    - `{:error, changeset}` on validation failure
  """
  def create_invitation(attrs) do
    %Invitation{}
    |> Invitation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a pending invitation by token.

  Returns nil if no matching invitation is found or if the invitation has been accepted.

  ## Parameters
    - token: The invitation token
  """
  def get_invitation_by_token(token) do
    Invitation
    |> where([i], i.token == ^token and is_nil(i.accepted_at))
    |> preload([:company])
    |> Repo.one()
  end

  @doc """
  Lists all pending invitations for a company.

  ## Parameters
    - company: The company struct
  """
  def list_pending_invitations(%Company{} = company) do
    Invitation
    |> where([i], i.company_id == ^company.id and is_nil(i.accepted_at))
    |> preload([:inviter])
    |> Repo.all()
  end

  @doc """
  Deletes a company invitation.

  Also broadcasts the deletion event.

  ## Parameters
    - invitation: The invitation struct to delete
  """
  def delete_invitation(%Invitation{} = invitation) do
    Repo.delete(invitation)
    |> case do
      {:ok, deleted_invitation} = result ->
        # Broadcast invitation deletion
        DataSync.broadcast("invitations", deleted_invitation.company_id,
          {:deleted, %{type: :invitation, id: deleted_invitation.id}}
        )
        DataSync.broadcast("user_invitations", deleted_invitation.email,
          {:deleted, %{type: :invitation, id: deleted_invitation.id}}
        )
        result
      error -> error
    end
  end

  @doc """
  Accepts a company invitation.

  Creates an employee record for the user, deletes the invitation,
  and broadcasts the relevant events.

  ## Parameters
    - invitation: The invitation struct to accept
    - user: The user accepting the invitation
  """
  def accept_invitation(%Invitation{} = invitation, user) do
    user = Core.Repo.preload(user, :profile)

    # First check if employee exists
    case Repo.get_by(Employee, email: user.email, company_id: invitation.company_id) do
      nil ->
        # Create new employee
        employee_changeset = Employee.changeset(%Employee{}, %{
          email: user.email,
          company_id: invitation.company_id,
          first_name: user.profile.first_name,
          last_name: user.profile.last_name,
          profile_id: user.profile.id
        })

        Repo.transaction(fn ->
          with {:ok, employee} <- Repo.insert(employee_changeset) do
            # Delete the accepted invitation
            Repo.delete(invitation)

            # Clean up other invitations
            {_deleted_count, _} = from(i in Invitation,
              where: i.email == ^user.email and
                     i.company_id == ^invitation.company_id and
                     i.id != ^invitation.id
            ) |> Repo.delete_all()

            # Preload associations before broadcasting
            employee = Repo.preload(employee, [:profile])

            # Broadcast invitation deletion
            DataSync.broadcast("invitations", invitation.company_id,
              {:deleted, %{type: :invitation, id: invitation.id}}
            )
            DataSync.broadcast("user_invitations", user.email,
              {:deleted, %{type: :invitation, id: invitation.id}}
            )

            # Broadcast new employee
            DataSync.broadcast("employees", invitation.company_id,
              {:created, %{type: :employee, employee: employee}}
            )
            DataSync.broadcast("employees", "all",
              {:created, %{type: :employee, employee: employee, global_scope: true}}
            )

            employee
          end
        end)

      employee ->
        # Delete the accepted invitation
        Repo.delete(invitation)

        # Clean up other invitations
        {_deleted_count, _} = from(i in Invitation,
          where: i.email == ^user.email and
                 i.company_id == ^invitation.company_id and
                 i.id != ^invitation.id
        ) |> Repo.delete_all()

        # Broadcast invitation deletion
        DataSync.broadcast("invitations", invitation.company_id,
          {:deleted, %{type: :invitation, id: invitation.id}}
        )
        DataSync.broadcast("user_invitations", user.email,
          {:deleted, %{type: :invitation, id: invitation.id}}
        )

        {:ok, employee}
    end
  end

  @doc """
  Verifies and processes a company invitation token.

  ## Parameters
    - token: The invitation token to verify

  ## Returns
    - `{:ok, %{company_id: id, email: email}}` if token is valid
    - `{:error, reason}` if token is invalid or expired
  """
  def verify_invitation_token(token) do
    case EndpointHelper.verify_token(:invitation, "company_invitation", token, max_age: 24 * 3600) do
      {:ok, %{company_id: company_id, email: email}} ->
        {:ok, %{company_id: company_id, email: email}}
      error -> error
    end
  end

  @doc """
  Lists all pending invitations for a user by email.

  ## Parameters
    - email: The email address to look up invitations for
  """
  def list_user_pending_invitations(email) do
    Invitation
    |> where([i], i.email == ^email and is_nil(i.accepted_at))
    |> preload([:inviter, :company])
    |> Repo.all()
  end

  @doc """
  Lists all companies where the user is an employee.

  ## Parameters
    - email: The email address of the user
    - opts: Additional options for pagination
      - `:page` - The page number (default: 1)
      - `:per_page` - Items per page (default: 10)
  """
  def list_companies_by_employee(email, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)

    Company
    |> join(:inner, [c], e in Employee, on: e.company_id == c.id)
    |> where([_c, e], e.email == ^email)
    |> offset((^page - 1) * ^per_page)
    |> limit(^per_page)
    |> Repo.all()
  end

  @doc """
  Gets an employee by company ID and email.

  ## Parameters
    - company_id: The ID of the company
    - email: The email address of the employee
  """
  def get_employee_by_company_and_email(company_id, email) do
    Employee
    |> where([e], e.company_id == ^company_id and e.email == ^email)
    |> Repo.one()
  end

  @doc """
  Gets an employee by user ID by looking up through the profile.

  ## Parameters
    - user_id: The ID of the user
  """
  def get_employee_by_user_id(user_id) do
    Employee
    |> join(:inner, [e], p in assoc(e, :profile))
    |> where([e, p], p.user_id == ^user_id)
    |> preload([e, p], [:profile])
    |> Repo.one()
  end
end
