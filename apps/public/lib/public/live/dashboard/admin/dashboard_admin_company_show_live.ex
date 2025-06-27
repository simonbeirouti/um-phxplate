defmodule Public.Dashboard.Admin.CompanyShowLive do
  @moduledoc """
  LiveView for detailed company management.

  This view provides comprehensive functionality to manage a specific company,
  including editing company details, managing employees, viewing activity timeline,
  handling employee invitations, and uploading company logos. It establishes
  various PubSub subscriptions to enable real-time updates.
  """
  use Public, :live_view

  alias Core.Companies
  alias Public.Components.ActivityTimelineComponent
  alias Public.Components.Upload.ImageUploadComponent
  alias Core.Authorization
  alias Public.PageMeta
  alias Core.PubSub.DataSync
  alias Core.Repo

  @doc """
  Mount hook to authorize access to company pages.

  Validates that the current user is authorized to access the requested company
  before allowing the LiveView to mount. Redirects unauthorized users.
  """
  def on_mount(:default, %{"id" => company_id}, _session, socket) do
    case authorize_company(company_id, socket.assigns.current_user) do
      {:ok, _company} ->
        {:cont, socket}

      {:error, _reason} ->
        {:halt,
         socket
         |> put_flash(:error, "You don't have access to this company")
         |> redirect(to: ~p"/dashboard/admin/companies")}
    end
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}

  @doc """
  Initializes the LiveView with company details and sets up PubSub subscriptions.

  Loads the company, its employees, activities, and pending invitations.
  Sets up subscriptions for real-time updates to companies, employees,
  invitations, users, and profiles.
  """
  @impl true
  def mount(%{"id" => company_id}, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("companies", company_id)
      DataSync.subscribe("employees", company_id)
      DataSync.subscribe("invitations", company_id)
      DataSync.subscribe("users", "all")
      DataSync.subscribe("profiles", "all")
    end

    case authorize_company(company_id, socket.assigns.current_user) do
      {:ok, company} ->
        employees = Companies.get_company_employees(company)
        activities = Core.Tracking.get_company_activities(company_id)
        pending_invitations = Companies.list_pending_invitations(company)

        socket =
          socket
          |> PageMeta.assign_metadata(
            title: "#{company.name} Details",
            description: "Company details and employee management",
            url: "/dashboard/admin/companies/#{company.id}"
          )
          |> assign(
            company: company,
            form:
              to_form(%{
                "name" => company.name,
                "email" => company.email,
                "phone" => company.phone,
                "website" => company.website,
                "address" => company.address,
                "description" => company.description,
                "logo" => company.logo
              }),
            employees: employees,
            activities: activities,
            show_edit_modal: false,
            selected_employee: nil,
            confirming_delete: MapSet.new(),
            invite_email: "",
            form_changed: false,
            pending_invitations: pending_invitations,
            confirming_delete_company: false,
            active_tab: "profile",
            show_invite_modal: false
          )

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have access to this company")
         |> redirect(to: ~p"/dashboard/admin/companies")}
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    {:noreply, assign(socket, :current_path, uri.path)}
  end

  @impl true
  def handle_info({:created, %{type: :employee, employee: new_employee}}, socket) do
    # The 'new_employee' from PubSub (e.g., from accept_invitation)
    # should already have its profile preloaded.
    # Check if an employee with this ID already exists in our current list.
    is_present =
      Enum.any?(socket.assigns.employees, fn existing_employee ->
        existing_employee.id == new_employee.id
      end)

    if is_present do
      # Employee is already in the list. Do nothing to prevent duplication.
      # Optionally, one could update the existing entry with new_employee data here
      # if there's a chance it might be fresher, but for a :created event,
      # simply avoiding duplication is the primary goal.
      {:noreply, socket}
    else
      # Employee is not in the list, so prepend it.
      {:noreply,
       update(socket, :employees, fn existing_employees ->
         [new_employee | existing_employees]
       end)}
    end
  end

  def handle_info({:updated, %{type: :employee, employee: employee}}, socket) do
    employee = Repo.preload(employee, [:profile])

    {:noreply,
     update(socket, :employees, fn employees ->
       Enum.map(employees, fn e -> if e.id == employee.id, do: employee, else: e end)
     end)}
  end

  def handle_info({:deleted, %{type: :employee, id: employee_id}}, socket) do
    updated_employees =
      Enum.reject(socket.assigns.employees, fn employee ->
        employee.id == employee_id
      end)

    {:noreply, assign(socket, :employees, updated_employees)}
  end

  def handle_info({:created, %{type: :invitation, invitation: invitation}}, socket) do
    invitation = Repo.preload(invitation, [:company, :inviter])

    {:noreply,
     update(socket, :pending_invitations, fn invitations -> [invitation | invitations] end)}
  end

  def handle_info({:updated, %{type: :invitation, invitation: invitation}}, socket) do
    invitation = Repo.preload(invitation, [:company, :inviter])

    {:noreply,
     update(socket, :pending_invitations, fn invitations ->
       Enum.map(invitations, fn inv -> if inv.id == invitation.id, do: invitation, else: inv end)
     end)}
  end

  def handle_info({:deleted, %{type: :invitation, id: invitation_id}}, socket) do
    {:noreply,
     update(socket, :pending_invitations, fn invitations ->
       Enum.reject(invitations, &(&1.id == invitation_id))
     end)}
  end

  def handle_info({:updated, %{type: :company, company: company}}, socket) do
    activities = Core.Tracking.get_company_activities(company.id)

    {:noreply,
     socket
     |> assign(:company, company)
     |> assign(:activities, activities)
     |> assign(
       :form,
       to_form(%{
         "name" => company.name,
         "email" => company.email,
         "phone" => company.phone,
         "website" => company.website,
         "address" => company.address,
         "description" => company.description,
         "logo" => company.logo
       })
     )}
  end

  def handle_info({:deleted, %{type: :company, id: company_id}}, socket) do
    if socket.assigns.company.id == company_id do
      {:noreply,
       socket
       |> put_flash(:error, "Company was deleted.")
       |> redirect(to: ~p"/dashboard/admin/companies")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted, %{type: :user, id: user_id}}, socket) do
    # Find employees associated with the deleted user
    employees_to_delete =
      Enum.filter(socket.assigns.employees, fn employee ->
        employee.profile && employee.profile.user_id == user_id
      end)

    # Delete each employee
    Enum.each(employees_to_delete, fn employee ->
      Companies.delete_employee(employee, socket.assigns.current_user)
    end)

    # Remove the employees from the view and refresh activities
    updated_employees =
      Enum.reject(socket.assigns.employees, fn employee ->
        employee.profile && employee.profile.user_id == user_id
      end)

    activities = Core.Tracking.get_company_activities(socket.assigns.company.id)

    {:noreply,
     socket
     |> assign(:employees, updated_employees)
     |> assign(:activities, activities)}
  end

  def handle_info({:deleted, %{type: :profile, id: profile_id}}, socket) do
    # Remove employees with deleted profiles
    updated_employees =
      Enum.reject(socket.assigns.employees, fn employee ->
        employee.profile && employee.profile.id == profile_id
      end)

    activities = Core.Tracking.get_company_activities(socket.assigns.company.id)

    {:noreply,
     socket
     |> assign(:employees, updated_employees)
     |> assign(:activities, activities)}
  end

  def handle_info({:deleted, %{type: :employee, employee: employee}}, socket) do
    # Remove the specific employee from the view
    updated_employees =
      Enum.reject(socket.assigns.employees, fn e ->
        e.id == employee.id
      end)

    activities = Core.Tracking.get_company_activities(socket.assigns.company.id)

    {:noreply,
     socket
     |> assign(:employees, updated_employees)
     |> assign(:activities, activities)}
  end

  def handle_info({:employee_deleted, %{type: :employee, id: employee_id}}, socket) do
    # Remove the specific employee from the view
    updated_employees =
      Enum.reject(socket.assigns.employees, fn employee ->
        employee.id == employee_id
      end)

    activities = Core.Tracking.get_company_activities(socket.assigns.company.id)

    {:noreply,
     socket
     |> assign(:employees, updated_employees)
     |> assign(:activities, activities)}
  end

  def handle_info({:close_modal, "invite_user_modal"}, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
  end

  # Handle global profile creation events
  def handle_info({:created, %{type: :profile, profile: new_profile, global_scope: true}}, socket) do
    updated_employees =
      Enum.map(socket.assigns.employees, fn employee ->
        # If employee is linked by user_id and this new_profile is for that user
        if employee.profile_id == nil && employee.user_id == new_profile.user_id do
          %{employee | profile: new_profile, profile_id: new_profile.id}
        else
          employee
        end
      end)

    {:noreply, assign(socket, :employees, updated_employees)}
  end

  # Handle global profile update events that CompanyShowLive might receive
  def handle_info(
        {:updated, %{type: :profile, profile: updated_profile, global_scope: true}},
        socket
      ) do
    updated_employees =
      Enum.map(socket.assigns.employees, fn employee ->
        cond do
          # Profile exists and IDs match
          employee.profile && employee.profile.id == updated_profile.id ->
            %{employee | profile: updated_profile}

          # Profile was nil, but profile_id matches (should ideally not happen if preloaded correctly but good fallback)
          !employee.profile && employee.profile_id == updated_profile.id ->
            %{employee | profile: updated_profile}

          # Employee is linked by user_id and this updated_profile is for that user
          employee.user_id == updated_profile.user_id ->
            %{employee | profile: updated_profile, profile_id: updated_profile.id}

          true ->
            employee
        end
      end)

    {:noreply, assign(socket, :employees, updated_employees)}
  end

  @impl true
  def handle_info({:image_uploaded, %{type: :logo, url: url, old_url: _old_url}}, socket) do
    case Companies.update_company(
           socket.assigns.company,
           %{"logo" => url},
           socket.assigns.current_user
         ) do
      {:ok, company} ->
        activities = Core.Tracking.get_company_activities(company.id)

        {:noreply,
         socket
         |> assign(:company, company)
         |> assign(:activities, activities)
         |> assign(
           :form,
           to_form(%{
             "name" => company.name,
             "email" => company.email,
             "phone" => company.phone,
             "website" => company.website,
             "address" => company.address,
             "description" => company.description,
             "logo" => company.logo
           })
         )
         |> put_flash(:info, "Company logo updated successfully.")}

      {:error, _changeset} ->
        # If the company update failed, try to delete the new image to avoid orphaned files
        if url do
          Task.start(fn -> Core.AWS.S3.delete_file(url) end)
        end

        {:noreply,
         socket
         |> put_flash(:error, "Failed to update company logo.")}
    end
  end

  def handle_info({:image_uploaded_error, %{error: error_msg}}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, error_msg)}
  end

  defp authorize_company(company_id, user) do
    with {:ok, id} <- parse_id(company_id),
         %Companies.Company{} = company <- Companies.get_company!(id),
         true <- Authorization.is_company_owner?(company, user) do
      {:ok, company}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  @impl true
  def handle_event("validate_company", params, socket) do
    form_data = %{
      "name" => socket.assigns.company.name,
      "email" => socket.assigns.company.email,
      "phone" => socket.assigns.company.phone,
      "website" => socket.assigns.company.website,
      "address" => socket.assigns.company.address,
      "description" => socket.assigns.company.description,
      "logo" => socket.assigns.company.logo
    }

    form_changed = params != form_data

    {:noreply,
     socket
     |> assign(:form, to_form(params))
     |> assign(:form_changed, form_changed)}
  end

  def handle_event("save_company", params, socket) do
    case Companies.update_company(socket.assigns.company, params, socket.assigns.current_user) do
      {:ok, company} ->
        activities = Core.Tracking.get_company_activities(company.id)

        {:noreply,
         socket
         |> assign(:company, company)
         |> assign(:activities, activities)
         |> assign(
           :form,
           to_form(%{
             "name" => company.name,
             "email" => company.email,
             "phone" => company.phone,
             "website" => company.website,
             "address" => company.address,
             "description" => company.description,
             "logo" => company.logo
           })
         )
         |> assign(:form_changed, false)
         |> put_flash(:info, "Company updated successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Error updating company.")}
    end
  end

  def handle_event("reset_company", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :form,
       to_form(%{
         "name" => socket.assigns.company.name,
         "email" => socket.assigns.company.email,
         "phone" => socket.assigns.company.phone,
         "website" => socket.assigns.company.website,
         "address" => socket.assigns.company.address,
         "description" => socket.assigns.company.description,
         "logo" => socket.assigns.company.logo
       })
     )
     |> assign(:form_changed, false)}
  end

  def handle_event("edit_employee", %{"id" => employee_id}, socket) do
    employee = Enum.find(socket.assigns.employees, &(&1.id == employee_id))
    {:noreply, assign(socket, show_edit_modal: true, selected_employee: employee)}
  end

  def handle_event("send_invite", %{"email" => email}, socket) do
    case Companies.invite_to_company(socket.assigns.company, email, socket.assigns.current_user) do
      {:ok, _invitation} ->
        activities = Core.Tracking.get_company_activities(socket.assigns.company.id)

        {:noreply,
         socket
         |> assign(:activities, activities)
         |> assign(:invite_email, "")
         |> put_flash(:info, "Invitation sent successfully to #{email}")
         |> assign(show_invite_modal: false)}

      {:error, %Ecto.Changeset{} = changeset} ->
        error_message =
          case changeset.errors do
            [{:email, {msg, _}}] -> msg
            [{:company_id, {msg, _}}] -> msg
            _ -> "Failed to send invitation. Please try again."
          end

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(:invite_email, email)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to send invitation. Please try again.")
         |> assign(:invite_email, email)}
    end
  end

  def handle_event("delete_employee", %{"id" => employee_id}, socket) do
    # Convert employee_id to integer since it comes as string from the template
    employee_id = String.to_integer(employee_id)

    if MapSet.member?(socket.assigns.confirming_delete, employee_id) do
      employee = Enum.find(socket.assigns.employees, &(&1.id == employee_id))

      case Companies.delete_employee(employee, socket.assigns.current_user) do
        {:ok, _deleted_employee} ->
          employees = Companies.get_company_employees(socket.assigns.company)
          activities = Core.Tracking.get_company_activities(socket.assigns.company.id)

          {:noreply,
           socket
           |> assign(:employees, employees)
           |> assign(:activities, activities)
           |> assign(
             :confirming_delete,
             MapSet.delete(socket.assigns.confirming_delete, employee_id)
           )
           |> put_flash(:info, "Employee deleted successfully.")}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> assign(
             :confirming_delete,
             MapSet.delete(socket.assigns.confirming_delete, employee_id)
           )
           |> put_flash(:error, "Could not delete employee.")}
      end
    else
      {:noreply,
       assign(socket,
         confirming_delete: MapSet.put(socket.assigns.confirming_delete, employee_id)
       )}
    end
  end

  def handle_event("cancel_invitation", %{"id" => invitation_id}, socket) do
    invitation_id = String.to_integer(invitation_id)
    invitation = Enum.find(socket.assigns.pending_invitations, &(&1.id == invitation_id))

    case Companies.delete_invitation(invitation) do
      {:ok, _deleted_invitation} ->
        pending_invitations = Companies.list_pending_invitations(socket.assigns.company)
        activities = Core.Tracking.get_company_activities(socket.assigns.company.id)

        {:noreply,
         socket
         |> assign(:pending_invitations, pending_invitations)
         |> assign(:activities, activities)
         |> put_flash(:info, "Invitation canceled successfully.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not cancel invitation.")}
    end
  end

  def handle_event("confirm_delete_company", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_company, true)}
  end

  def handle_event("show_invite_modal", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("set_active_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("cancel_delete_company", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_company, false)}
  end

  def handle_event("delete_company", _params, socket) do
    case Companies.delete_company(socket.assigns.company) do
      {:ok, _deleted_company} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company deleted successfully.")
         |> redirect(to: ~p"/dashboard/admin/companies")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete company.")
         |> assign(:confirming_delete_company, false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        {@company.name}
        <:subtitle>
          {@company.description}
        </:subtitle>
      </.header>

      <div role="tablist" class="tabs tabs-lift mt-4">
        <input
          type="radio"
          name="company_tabs"
          role="tab"
          class="tab"
          aria-label="Profile"
          checked={@active_tab == "profile"}
          phx-click="set_active_tab"
          phx-value-tab="profile"
        />
        <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
          <div class="space-y-4">
            <div class="flex justify-center">
              <.live_component
                module={ImageUploadComponent}
                id="company-logo"
                type={:logo}
                image_url={@form[:logo].value}
                entity_type={:company}
                entity_id={@company.id}
                on_upload_complete="image_uploaded"
              />
            </div>
            <form phx-change="validate_company" phx-submit="save_company" class="space-y-6">
              <div class="grid grid-cols-2 gap-4">
                <div class="col-span-2 sm:col-span-1">
                  <label class="label">
                    <span class="label-text">Name</span>
                  </label>
                  <input
                    type="text"
                    name="name"
                    value={@form[:name].value}
                    placeholder="Enter company name"
                    class="input input-bordered w-full"
                  />
                </div>
                <div class="col-span-2 sm:col-span-1">
                  <label class="label">
                    <span class="label-text">Email</span>
                  </label>
                  <input
                    type="email"
                    name="email"
                    value={@form[:email].value}
                    placeholder="your@company.com"
                    class="input input-bordered w-full"
                  />
                </div>
                <div class="col-span-2 sm:col-span-1">
                  <label class="label">
                    <span class="label-text">Phone</span>
                  </label>
                  <input
                    type="tel"
                    name="phone"
                    value={@form[:phone].value}
                    placeholder="123-456-7890"
                    class="input input-bordered w-full"
                  />
                </div>
                <div class="col-span-2 sm:col-span-1">
                  <label class="label">
                    <span class="label-text">Website</span>
                  </label>
                  <input
                    type="url"
                    name="website"
                    value={@form[:website].value}
                    placeholder="https://www.company.com"
                    class="input input-bordered w-full"
                  />
                </div>
                <div class="col-span-2 sm:col-span-1">
                  <label class="label">
                    <span class="label-text">Address</span>
                  </label>
                  <input
                    type="text"
                    name="address"
                    value={@form[:address].value}
                    placeholder="123 Main St, Anytown, USA"
                    class="input input-bordered w-full"
                  />
                </div>
                <div class="col-span-2">
                  <label class="label">
                    <span class="label-text">Description</span>
                  </label>
                  <textarea
                    name="description"
                    placeholder="Enter company description"
                    class="textarea textarea-bordered w-full"
                  >{@form[:description].value}</textarea>
                </div>
              </div>
              <div class="flex flex-col gap-4 lg:flex-row lg:justify-between w-full">
                <div :if={@form_changed} class="flex flex-col gap-3 lg:flex-row lg:gap-3 lg:w-1/2">
              <button
                type="button"
                class="btn w-full"
                phx-click="close"
                phx-target="#invite_user_modal"
              >
                Cancel
              </button>
                  <button :if={@form_changed} type="submit" class="btn btn-primary w-full">Save Changes</button>
                </div>
                <div class="flex justify-end w-full lg:w-1/2">
                  <%= if @confirming_delete_company do %>
                    <div class="flex flex-col gap-3 lg:flex-row lg:gap-3 w-full">
                      <button
                        type="button"
                        class="btn btn-error w-full"
                        phx-click="delete_company"
                      >
                        Confirm Delete
                      </button>
                      <button
                        type="button"
                        class="btn w-full"
                        phx-click="cancel_delete_company"
                      >
                        Cancel
                      </button>
                    </div>
                  <% else %>
                    <button
                      type="button"
                      class="btn btn-error w-full"
                      phx-click="confirm_delete_company"
                    >
                      Delete Company
                    </button>
                  <% end %>
                </div>
              </div>
            </form>
          </div>
        </div>

        <input
          type="radio"
          name="company_tabs"
          role="tab"
          class="tab"
          aria-label="Employees"
          checked={@active_tab == "employees"}
          phx-click="set_active_tab"
          phx-value-tab="employees"
        />
        <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
          {render_employees_tab(assigns)}
        </div>

        <input
          type="radio"
          name="company_tabs"
          role="tab"
          class="tab"
          aria-label="Timeline"
          checked={@active_tab == "timeline"}
          phx-click="set_active_tab"
          phx-value-tab="timeline"
        />
        <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
          <.live_component
            module={ActivityTimelineComponent}
            id={"activity-timeline-#{@company.id}"}
            activities={@activities}
            company_id={@company.id}
            show_timestamps={true}
            timestamps={
              %{
                inserted_at: @company.inserted_at,
                updated_at: @company.updated_at
              }
            }
          />
        </div>
      </div>
      <.live_component
        module={Public.Components.ModalComponent}
        id="invite_user_modal"
        title="Invite New User"
        show={@show_invite_modal}
      >
        <form phx-submit="send_invite" id="invite_user_form" class="space-y-4">
          <fieldset class="space-y-4 form-control w-full">
            <input
              type="email"
              name="email"
              placeholder="user@example.com"
              class="input w-full input-bordered"
              required
            />
          </fieldset>
          <div class="flex flex-col w-full space-y-2">
            <button type="submit" class="btn btn-primary w-full" form="invite_user_form">
              Send Invite
            </button>
            <button
              type="button"
              class="btn w-full"
              phx-click="close_modal"
            >
              Cancel
            </button>
          </div>
        </form>
      </.live_component>
    </div>
    """
  end

  defp render_employees_tab(assigns) do
    # Combine employees and pending invitations into a single rows list
    all_rows = assigns.employees ++ Enum.map(assigns.pending_invitations, fn invitation ->
      %{
        type: :invitation,
        id: invitation.id,
        email: invitation.email,
        invitation: invitation
      }
    end)

    assigns = assign(assigns, :all_rows, all_rows)

    ~H"""
    <div class="space-y-4">
      <div class="hidden lg:block overflow-x-auto">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th>Photo</th>
              <th>Name</th>
              <th>Email</th>
              <th>Phone</th>
              <th>Position</th>
              <th>Department</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @all_rows do %>
              <tr>
                <td>
                  <div class="flex items-center gap-2">
                    <%= if Map.get(row, :type) == :invitation do %>
                      <span class="text-sm text-base-content/70">Pending Invite</span>
                    <% else %>
                      <div class="avatar">
                        <div class="w-12 rounded-full">
                          <img
                            src={
                              if row.profile,
                                do: row.profile.avatar_url || "/images/avatar.jpg",
                                else: "/images/avatar.jpg"
                            }
                            alt="Employee avatar"
                          />
                        </div>
                      </div>
                    <% end %>
                  </div>
                </td>
                <td class="font-medium">
                  <%= if Map.get(row, :type) == :invitation do %>
                    {row.email}
                  <% else %>
                    <%= if row.profile do
                      "#{row.profile.first_name} #{row.profile.last_name}"
                    else
                      "Profile Deleted"
                    end %>
                  <% end %>
                </td>
                <td>
                  <%= if Map.get(row, :type) == :invitation do %>
                    N/A
                  <% else %>
                    {row.email}
                  <% end %>
                </td>
                <td>
                  <%= if Map.get(row, :type) == :invitation do %>
                    N/A
                  <% else %>
                    <%= if row.profile, do: row.profile.phone || "N/A", else: "N/A" %>
                  <% end %>
                </td>
                <td>
                  <%= if Map.get(row, :type) == :invitation do %>
                    N/A
                  <% else %>
                    {row.position || "N/A"}
                  <% end %>
                </td>
                <td>
                  <%= if Map.get(row, :type) == :invitation do %>
                    N/A
                  <% else %>
                    {row.department || "N/A"}
                  <% end %>
                </td>
                <td class="text-right">
                  <%= if Map.get(row, :type) == :invitation do %>
                    <button
                      class="btn btn-error btn-sm"
                      phx-click="cancel_invitation"
                      phx-value-id={row.id}
                    >
                      Cancel
                    </button>
                  <% else %>
                    <button
                      class="btn btn-error btn-sm"
                      phx-click="delete_employee"
                      phx-value-id={row.id}
                    >
                      <%= if MapSet.member?(@confirming_delete, row.id) do %>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
                        </svg>
                      <% else %>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                        </svg>
                      <% end %>
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <div class="flex justify-start mt-4">
          <button class="btn btn-primary" phx-click="show_invite_modal">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-4 h-4 mr-2"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            Invite User
          </button>
        </div>
      </div>

      <div class="lg:hidden space-y-4 h-[calc(100vh-250px)]" id="mobile-employees-container">
        <%= for invitation <- @pending_invitations do %>
          <div class="bg-gray-100/80 rounded-lg p-4 relative">
            <div class="flex justify-between items-center">
              <div>
                <span class="text-sm font-medium text-gray-700">Pending Invitation:</span>
                <span class="text-sm text-gray-600">{invitation.email}</span>
              </div>
              <div class="group relative" phx-click="cancel_invitation" phx-value-id={invitation.id}>
                <button
                  class="btn btn-error btn-sm opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        <% end %>
        <%= for employee <- @employees do %>
          <div class="bg-white shadow rounded-lg p-4">
            <div class="flex justify-between items-start mb-4">
              <div>
                <h3 class="text-lg font-medium">
                  <%= if employee.profile do
                    "#{employee.profile.first_name} #{employee.profile.last_name}"
                  else
                    "Profile Deleted"
                  end %>
                </h3>
                <p class="text-sm text-gray-500">{employee.position || "No position"}</p>
              </div>

              <div>
                <div class="relative inline-block text-left">
                  <button
                    class="btn btn-outline btn-sm mb-2"
                    phx-click={JS.toggle(to: "#dropdown-#{employee.id}-card")}
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M6.75 12a.75.75 0 11-1.5 0 .75.75 0 011.5 0zM12.75 12a.75.75 0 11-1.5 0 .75.75 0 011.5 0zM18.75 12a.75.75 0 11-1.5 0 .75.75 0 011.5 0z" />
                    </svg>
                  </button>
                  <div
                    id={"dropdown-#{employee.id}-card"}
                    class="hidden absolute right-0 w-48 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 divide-y divide-gray-100"
                  >
                    <button
                      class="group flex w-full items-center px-4 py-2 text-sm text-red-600 hover:bg-gray-100"
                      phx-click="delete_employee"
                      phx-value-id={employee.id}
                    >
                      <%= if MapSet.member?(@confirming_delete, employee.id) do %>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="mr-2 h-4 w-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
                        </svg>
                        Confirm Delete
                      <% else %>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="mr-2 h-4 w-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                        </svg>
                        Delete Employee
                      <% end %>
                    </button>
                  </div>
                </div>
              </div>
            </div>
            <dl class="grid grid-cols-1 gap-2 text-sm">
              <div>
                <dt class="text-gray-500">Email</dt>
                <dd>{employee.email}</dd>
              </div>
              <div>
                <dt class="text-gray-500">Phone</dt>
                <dd><%= if employee.profile, do: employee.profile.phone || "N/A", else: "N/A" %></dd>
              </div>
              <div>
                <dt class="text-gray-500">Department</dt>
                <dd>{employee.department || "N/A"}</dd>
              </div>
            </dl>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
