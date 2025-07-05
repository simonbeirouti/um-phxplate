defmodule Admin.CompaniesLive do
  @moduledoc """
  LiveView for super admin company management.

  This view provides comprehensive functionality for super admins to manage companies,
  including viewing company details, employees, and activity timelines. It features
  real-time updates via PubSub subscriptions, pagination, and company deletion capabilities.
  """
  use Admin, :live_view
  alias Core.{Companies, Repo}
  alias Admin.{PageMeta, Components.ActivityTimelineComponent}
  alias Core.PubSub.DataSync
  alias Phoenix.LiveView.JS

  @doc """
  Initializes the LiveView with paginated companies list and PubSub subscriptions.

  Sets up subscriptions for company, employee, and profile updates,
  and initializes the socket assigns with empty values for the
  selected company and activities.
  """
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("companies", "all")
      DataSync.subscribe("employees", "all")
      DataSync.subscribe("profiles", "all")
    end

    socket =
      socket
      |> assign(:selected_company, nil)
      |> assign(:activities, [])
      |> assign(:confirming_delete_company, false)
      |> assign(:show_drawer, false)
      |> PageMeta.assign_metadata(
        title: "Companies Management",
        description: "Manage companies across the application",
        url: "/dashboard/super_admin/companies"
      )

    {:ok, load_companies(socket, 1)}
  end

  @impl true
  def handle_info({:created, %{type: :company, company: _company}}, socket) do
    # Instead of just appending, reload the companies for the current page
    {:noreply, load_companies(socket, socket.assigns.page)}
  end

  def handle_info({:updated, %{type: :company, company: company}}, socket) do
    company = Repo.preload(company, [:employees])

    socket =
      socket
      |> update(:companies, fn companies ->
        Enum.map(companies, fn c -> if c.id == company.id, do: company, else: c end)
      end)
      |> maybe_update_selected_company(company)

    {:noreply, socket}
  end

  def handle_info({:deleted, %{type: :company, id: company_id}}, socket) do
    # Clear selected company if it was deleted
    socket =
      if socket.assigns.selected_company && socket.assigns.selected_company.id == company_id do
        socket
        |> assign(:selected_company, nil)
        |> assign(:activities, [])
        |> assign(:confirming_delete_company, false)
        |> put_flash(:info, "Selected company was deleted.")
      else
        socket
      end

    # Reload the companies list to ensure proper pagination
    {:noreply, load_companies(socket, socket.assigns.page)}
  end

  def handle_info({:deleted, %{type: :employee, employee: employee}}, socket) do
    if socket.assigns.selected_company &&
         employee.company_id == socket.assigns.selected_company.id do
      # Update the selected company's employees list by removing the deleted employee
      socket =
        update(socket, :selected_company, fn company ->
          %{company | employees: Enum.reject(company.employees, &(&1.id == employee.id))}
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted, %{type: :employee, id: employee_id}}, socket) do
    if socket.assigns.selected_company do
      # Update the selected company's employees list by removing the deleted employee
      socket =
        update(socket, :selected_company, fn company ->
          %{company | employees: Enum.reject(company.employees, &(&1.id == employee_id))}
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:created, %{type: :employee, employee: new_employee}}, socket) do
    selected_company = socket.assigns.selected_company

    if selected_company && new_employee.company_id == selected_company.id do
      # Check if the employee already exists in the selected company's list
      is_present =
        Enum.any?(selected_company.employees, fn existing_employee ->
          existing_employee.id == new_employee.id
        end)

      if is_present do
        # Employee already in the list for the selected company, do nothing.
        {:noreply, socket}
      else
        # Add the new employee to the selected company's employee list
        updated_selected_company =
          %{selected_company | employees: [new_employee | selected_company.employees]}

        # Also update the main companies list if the selected company is in it
        updated_companies_list =
          Enum.map(socket.assigns.companies, fn company_in_list ->
            if company_in_list.id == updated_selected_company.id do
              updated_selected_company
            else
              company_in_list
            end
          end)

        {:noreply,
         assign(socket,
           selected_company: updated_selected_company,
           companies: updated_companies_list
         )}
      end
    else
      # Event is not for the currently selected company, or no company selected.
      {:noreply, socket}
    end
  end

  def handle_info({:deleted, %{type: :profile, profile: profile}}, socket) do
    if socket.assigns.selected_company do
      # Update the employee's profile in the selected company's employees list
      socket =
        update(socket, :selected_company, fn company ->
          updated_employees =
            Enum.map(company.employees, fn employee ->
              if employee.profile && employee.profile.id == profile.id do
                %{employee | profile: nil}
              else
                employee
              end
            end)

          %{company | employees: updated_employees}
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp maybe_update_selected_company(socket, company) do
    if socket.assigns.selected_company && socket.assigns.selected_company.id == company.id do
      assign(socket, :selected_company, company)
    else
      socket
    end
  end

  @impl true
  def handle_event("select_company", %{"id" => company_id}, socket) do
    case Integer.parse(company_id) do
      {id, ""} ->
        try do
          company = Companies.get_company!(id) |> Repo.preload([:employees])
          activities = Core.Tracking.get_company_activities(id, 20)

          {:noreply,
           assign(socket, selected_company: company, activities: activities, show_drawer: true)}
        rescue
          Ecto.NoResultsError ->
            {:noreply,
             socket
             |> put_flash(:error, "Company not found or was deleted.")
             |> assign(:selected_company, nil)
             |> assign(:activities, [])
             |> assign(:show_drawer, false)}
        end

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid company ID format.")
         |> assign(:selected_company, nil)
         |> assign(:activities, [])
         |> assign(:show_drawer, false)}
    end
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    {:noreply, load_companies(socket, page)}
  end

  def handle_event("confirm_delete_company", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_company, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirming_delete_company, false)}
  end

  def handle_event("delete_company", _params, socket) do
    case Companies.delete_company(socket.assigns.selected_company) do
      {:ok, _deleted_company} ->
        {:noreply,
         socket
         |> assign(:selected_company, nil)
         |> assign(:confirming_delete_company, false)
         |> assign(:show_drawer, false)
         |> put_flash(:info, "Company deleted successfully.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete company.")
         |> assign(:confirming_delete_company, false)}
    end
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, show_drawer: false)}
  end

  @impl true
  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    socket = update(socket, :layout_data, &Map.put(&1, :current_path, uri.path))
    {:noreply, socket}
  end

  defp load_companies(socket, page) do
    per_page = 10

    # Get total count for pagination
    total_companies = Companies.count_companies()
    total_pages = max(1, ceil(total_companies / per_page))

    # Get paginated companies
    companies =
      Companies.list_companies(page: page, per_page: per_page)
      |> Repo.preload([:employees])

    socket
    |> assign(:companies, companies)
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:per_page, per_page)
  end

  @doc """
  Renders the companies management view with companies list and detail panels.

  Displays a paginated list of companies and a tabbed interface for viewing
  company details, employees, and activity timeline when a company is selected.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        Companies Management
        <:subtitle>Manage companies across the application</:subtitle>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mt-4 h-[calc(100vh-200px)]">
        <div class="h-[calc(100vh-200px)] col-span-1">
          <h2 class="text-xl font-semibold mb-4">Company List</h2>
          <div class="divide-y">
            <%= for company <- @companies do %>
              <div class={"cursor-pointer p-3 rounded-md hover:bg-gray-50 relative #{if @selected_company && @selected_company.id == company.id, do: "bg-gray-100 border-l-4 border-blue-500", else: ""}"}
                phx-click="select_company"
                phx-value-id={company.id}
              >
                <!-- Company content -->
                <div class="flex justify-between items-center">
                  <h4 class="text-sm font-medium text-gray-900">{company.name}</h4>
                </div>
                <div class="mt-1">
                  <p class="text-xs text-gray-500">
                    Created: {Calendar.strftime(company.inserted_at, "%B %d, %Y at %H:%M")}
                  </p>
                </div>
              </div>
            <% end %>
          </div>

          <%= if @total_pages > 1 do %>
            <div class="mt-6">
              <div class="join w-full flex justify-center items-center">
                <%= if @page > 1 do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={@page - 1}>
                    <.icon name="hero-arrow-left" class="w-3.5 h-3.5" />
                  </button>
                <% end %>

                <%= for page_num <- max(1, @page - 2)..min(@total_pages, @page + 2) do %>
                  <button
                    class={"join-item btn #{if page_num == @page, do: "btn-active"}"}
                    phx-click="paginate"
                    phx-value-page={page_num}
                  >
                    {page_num}
                  </button>
                <% end %>

                <%= if @page < @total_pages do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={@page + 1}>
                    <.icon name="hero-arrow-right" class="w-3.5 h-3.5" />
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

    <!-- Desktop Details View (hidden on mobile) -->
        <div class="hidden lg:block col-span-1">
          <h2 class="text-xl font-semibold mb-4">Company Details</h2>
          <%= if @selected_company do %>
            {render_company_details(assign(assigns, :context, "desktop"))}
          <% else %>
            <p class="text-gray-500">Select a company to view details</p>
          <% end %>
        </div>
      </div>

    <!-- Mobile Drawer -->
      <div class="lg:hidden">
        <div class={"drawer drawer-bottom #{if @show_drawer and @selected_company != nil, do: "drawer-open"}"}>
          <input id="mobile-company-drawer" type="checkbox" class="drawer-toggle" checked={@show_drawer and @selected_company != nil} />
          <div class="drawer-content">
            <!-- Page content here -->
          </div>
          <div class="drawer-side">
            <label for="mobile-company-drawer" class="drawer-overlay" phx-click="close_drawer"></label>
            <div class="menu p-4 w-full h-3/4 bg-base-200 text-base-content">
              <h2 class="text-lg font-bold">Company Details</h2>
              <%= if @selected_company do %>
                <p class="text-sm mb-4">{@selected_company.name}</p>
              <% end %>
              <%= if @selected_company do %>
                {render_company_details(assign(assigns, :context, "mobile"))}
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Extract the company details rendering into a separate function for reuse
  defp render_company_details(assigns) do
    # Add a context to make component IDs unique
    context = assigns[:context] || "desktop"
    assigns = assign(assigns, :context, context)

    ~H"""
    <div role="tablist" class="tabs tabs-lifted">
      <input type="radio" name="company_tabs_#{@context}" role="tab" class="tab" aria-label="Details" checked />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <div class="space-y-4 p-2">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <h4 class="text-sm font-medium text-gray-500">Company Name</h4>
              <p class="mt-1">{@selected_company.name}</p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Description</h4>
              <p class="mt-1">{@selected_company.description || "No description provided"}</p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Contact Email</h4>
              <p class="mt-1">{@selected_company.email || "No email provided"}</p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Phone</h4>
              <p class="mt-1">{@selected_company.phone || "No phone provided"}</p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Address</h4>
              <p class="mt-1">{@selected_company.address || "No address provided"}</p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-gray-500">Website</h4>
              <p class="mt-1">
                <%= if @selected_company.website do %>
                  <a
                    href={@selected_company.website}
                    target="_blank"
                    class="text-primary-600 hover:text-primary-700"
                  >
                    {@selected_company.website}
                  </a>
                <% else %>
                  No website provided
                <% end %>
              </p>
            </div>
          </div>
          <div class="pt-4 border-t w-full">
            <%= if @confirming_delete_company do %>
              <div class="flex w-full justify-between space-x-4">
                <button type="button" class="btn btn-error w-full" phx-click="delete_company">
                  Confirm Delete
                </button>
                <button type="button" class="btn btn-outline w-full" phx-click="cancel_delete">
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
      </div>

      <input type="radio" name="company_tabs_#{@context}" role="tab" class="tab" aria-label="Employees" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <div class="space-y-4 p-2">
          <%= if Enum.any?(@selected_company.employees) do %>
            <div class="divide-y">
              <%= for employee <- @selected_company.employees do %>
                <div class="flex items-center justify-between py-2">
                  <div>
                    <p class="font-medium">
                      {employee.profile.first_name} {employee.profile.last_name}
                    </p>
                    <p class="text-sm text-gray-500">{employee.email}</p>
                    <p class="text-sm text-gray-500">Position: {employee.position}</p>
                    <p class="text-sm text-gray-500">Department: {employee.department}</p>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-gray-500">No employees found for this company</p>
          <% end %>
        </div>
      </div>

      <input type="radio" name="company_tabs_#{@context}" role="tab" class="tab" aria-label="Timeline" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <%= if @selected_company do %>
          <.live_component
            module={ActivityTimelineComponent}
            id={"activity-timeline-company-#{@selected_company.id}-#{@context}"}
            activities={@activities}
            company_id={@selected_company.id}
            show_timestamps={true}
            timestamps={
              %{
                inserted_at: @selected_company.inserted_at,
                updated_at: @selected_company.updated_at
              }
            }
          />
        <% end %>
      </div>
    </div>
    """
  end
end
