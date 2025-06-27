defmodule Public.Dashboard.Admin.AdminLive do
  @moduledoc """
  LiveView for the admin dashboard.

  This view displays an overview of all companies owned by the current user,
  including summary statistics and a grid of company cards. It subscribes to
  real-time updates for companies and employees, and provides functionality
  to create new companies.
  """
  use Public, :live_view
  alias Core.{Companies, Subscriptions}
  alias Core.PubSub.DataSync
  alias Public.PageMeta
  import Public.Dashboard.Admin.CompanyHelpers

  @doc """
  Initializes the LiveView with companies data and subscriptions.

  Loads companies owned by the current user, calculates total employee count,
  sets up PubSub subscriptions for real-time updates, and determines the
  company creation limit based on the user's subscription plan.
  """
  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    if connected?(socket) do
      # Subscribe to both user-specific and global company updates
      DataSync.subscribe("companies", current_user.id)
      DataSync.subscribe("companies", "all")
      # Subscribe to employee updates for all companies; will filter relevance in handle_info
      DataSync.subscribe("employees", "all")
      # Subscribe to user-specific events for force logout
      DataSync.subscribe("users", current_user.id)
    end

    companies = Companies.list_companies_by_owner(current_user.id)
    employee_count = calculate_employee_count(companies)

    # For super admin, we pass nil subscription which will give unlimited access
    subscription = if current_user.role == :super_admin do
      %{plan: %{features: %{"projects" => "Unlimited"}}}
    else
      Subscriptions.get_user_subscription(current_user.id)
    end

    {:ok,
     socket
     |> PageMeta.assign_metadata(
       title: "Admin Dashboard",
       description: "View your dashboard and companies that you've created",
       url: "/dashboard/admin"
     )
     |> assign(
       companies: companies,
       employee_count: employee_count,
       subscription: subscription,
       show_create_company_modal: false
     )}
  end

  @impl true
  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    {:noreply, assign(socket, :current_path, uri.path)}
  end

  @impl true
  def handle_info({:created, %{type: :company, company: company}}, socket) do
    # Only add the company if it belongs to the current user and isn't already in the list
    if company.owner_id == socket.assigns.current_user.id and not Enum.any?(socket.assigns.companies, &(&1.id == company.id)) do
      updated_companies = [company | socket.assigns.companies]
      employee_count = calculate_employee_count(updated_companies)
      {:noreply, assign(socket, companies: updated_companies, employee_count: employee_count)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:updated, %{type: :company, company: company}}, socket) do
    # Only update if it's one of our companies
    if company.owner_id == socket.assigns.current_user.id do
      updated_companies =
        Enum.map(socket.assigns.companies, fn c -> if c.id == company.id, do: company, else: c end)
      employee_count = calculate_employee_count(updated_companies)
      {:noreply, assign(socket, companies: updated_companies, employee_count: employee_count)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted, %{type: :company, id: company_id}}, socket) do
    updated_companies = Enum.reject(socket.assigns.companies, &(&1.id == company_id))
    employee_count = calculate_employee_count(updated_companies)
    {:noreply, assign(socket, companies: updated_companies, employee_count: employee_count)}
  end

  # Handle employee creation
  def handle_info({:created, %{type: :employee, employee: employee_data}}, socket) do
    current_user_id = socket.assigns.current_user.id
    # Check if the employee's company is owned by the current user
    company = Companies.get_company(employee_data.company_id)

    if company && company.owner_id == current_user_id do
      # Re-fetch companies for the current user to get updated employee lists
      companies = Companies.list_companies_by_owner(current_user_id)
      employee_count = calculate_employee_count(companies)
      {:noreply, assign(socket, companies: companies, employee_count: employee_count)}
    else
      {:noreply, socket}
    end
  end

  # Handle employee update
  def handle_info({:updated, %{type: :employee, employee: employee_data}}, socket) do
    current_user_id = socket.assigns.current_user.id
    company = Companies.get_company(employee_data.company_id)

    if company && company.owner_id == current_user_id do
      companies = Companies.list_companies_by_owner(current_user_id)
      employee_count = calculate_employee_count(companies)
      {:noreply, assign(socket, companies: companies, employee_count: employee_count)}
    else
      {:noreply, socket}
    end
  end

  # Handle employee deletion
  def handle_info({:deleted, %{type: :employee, employee: employee_data}}, socket) do
    current_user_id = socket.assigns.current_user.id
    # We need the company_id from the deleted employee data.
    # The broadcast for delete_employee in companies.ex sends the full employee struct.
    company = Companies.get_company(employee_data.company_id)

    if company && company.owner_id == current_user_id do
      companies = Companies.list_companies_by_owner(current_user_id)
      employee_count = calculate_employee_count(companies)
      {:noreply, assign(socket, companies: companies, employee_count: employee_count)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:close_modal, "create_company_modal"}, socket) do
    {:noreply, assign(socket, :show_create_company_modal, false)}
  end

  def handle_event("set_screen_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode)}
  end

  def handle_event("show_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_company_modal, true)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :show_create_company_modal, false)}
  end

  def handle_event("create_company", params, socket) do
    case handle_create_company(socket, params) do
      {:noreply, socket_after_create} ->
        # On success (no error flash), we close the modal by updating the assign.
        if Phoenix.LiveView.get_flash(socket_after_create, :error) == nil do
          {:noreply, assign(socket_after_create, :show_create_company_modal, false)}
        else
          {:noreply, socket_after_create}
        end

      other ->
        other
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        Admin Dashboard
        <:subtitle>
          View your dashboard here and companies that you've created
        </:subtitle>
      </.header>

      <div class="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6">
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <div class="flex items-center">
              <div class="p-3 bg-info/10 rounded-lg">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6 text-info">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 21h19.5m-18-18v18m2.25-18v18m13.5-18v18m2.25-18v18M6.75 9h.75m-.75 3h.75m-.75 3h.75m3-6h.75m-.75 3h.75m-.75 3h.75M6.75 21v-3.375c0-.621.504-1.125 1.125-1.125h.75c.621 0 1.125.504 1.125 1.125V21M3 3h12m-.75 4.5H21m-3.75 3.75h.75m-3 0h.75m-3 0h.75m-3 0h.75m-3 0h.75" />
                </svg>
              </div>
              <div class="ml-4">
                <h3 class="card-title text-base-content">Total Companies</h3>
                <p class="text-2xl font-bold text-info"><%= length(@companies) %></p>
              </div>
            </div>
          </div>
        </div>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <div class="flex items-center">
              <div class="p-3 bg-success/10 rounded-lg">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6 text-success">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z" />
                </svg>
              </div>
              <div class="ml-4">
                <h3 class="card-title text-base-content">Total Employees</h3>
                <p class="text-2xl font-bold text-success">
                  <%= @employee_count %>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="mt-6">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-xl font-semibold text-base-content">Your Companies</h2>
          <button class="btn btn-primary" phx-click="show_create_modal">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            Create Company
          </button>
        </div>

        <%= if Enum.empty?(@companies) do %>
          <div class="text-center py-12">
            <div class="text-base-content/50">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="mx-auto h-12 w-12">
                <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 21h19.5m-18-18v18m2.25-18v18m13.5-18v18m2.25-18v18M6.75 9h.75m-.75 3h.75m-.75 3h.75m3-6h.75m-.75 3h.75m-.75 3h.75M6.75 21v-3.375c0-.621.504-1.125 1.125-1.125h.75c.621 0 1.125.504 1.125 1.125V21M3 3h12m-.75 4.5H21m-3.75 3.75h.75m-3 0h.75m-3 0h.75m-3 0h.75m-3 0h.75" />
              </svg>
              <h3 class="mt-2 text-sm font-semibold text-base-content">No companies yet</h3>
              <p class="mt-1 text-sm text-base-content/70">Get started by creating your first company.</p>
            </div>
          </div>
        <% else %>
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <%= for company <- @companies do %>
              <.link navigate={~p"/dashboard/admin/companies/#{company.id}"} class="block">
                <div class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow duration-200">
                  <figure class="h-48 bg-base-200">
                    <%= if company.logo do %>
                      <img src={company.logo} alt={company.name} class="h-full w-full object-cover" />
                    <% else %>
                      <div class="flex items-center justify-center h-full">
                        <div class="text-4xl font-bold text-base-content/50">
                          <%= String.first(company.name) %>
                        </div>
                      </div>
                    <% end %>
                  </figure>
                  <div class="card-body">
                    <h3 class="card-title text-base-content"><%= company.name %></h3>
                    <%= if company.description do %>
                      <p class="text-base-content/70 line-clamp-2"><%= company.description %></p>
                    <% end %>
                    <div class="card-actions justify-end">
                      <div class="badge badge-outline">
                        <%= length(Companies.get_company_employees(company)) %> employees
                      </div>
                    </div>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>

      <.live_component
        module={Public.Components.ModalComponent}
        id="create_company_modal"
        title="Create New Company"
        show={@show_create_company_modal}
      >
        <form phx-submit="create_company" id="create_company_form" class="space-y-4">
          <fieldset class="space-y-4 form-control w-full">
            <input
              type="text"
              name="name"
              placeholder="Enter company name"
              class="input w-full input-bordered"
              required
            />
            <input
              type="email"
              name="email"
              placeholder="company@example.com"
              class="input w-full input-bordered"
            />
            <input
              type="tel"
              name="phone"
              placeholder="123-456-7890"
              class="input w-full input-bordered"
            />
            <input
              type="url"
              name="website"
              placeholder="https://company.com"
              class="input w-full input-bordered"
            />
            <input
              type="text"
              name="address"
              placeholder="123 Main St, City, State"
              class="input w-full input-bordered"
            />
            <textarea
              name="description"
              placeholder="Company description"
              class="textarea w-full textarea-bordered"
            >
            </textarea>
          </fieldset>
          <div class="flex flex-col w-full space-y-2">
            <button type="submit" class="btn btn-primary w-full" form="create_company_form">
              Create Company
            </button>
            <button type="button" class="btn w-full" phx-click="close">
              Cancel
            </button>
          </div>
        </form>
      </.live_component>
    </div>
    """
  end

  defp calculate_employee_count(companies) do
    Enum.reduce(companies, 0, fn company, acc ->
      acc + length(Companies.get_company_employees(company))
    end)
  end
end
