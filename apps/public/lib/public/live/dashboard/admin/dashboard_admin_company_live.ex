defmodule Public.Dashboard.Admin.CompanyLive do
  @moduledoc """
  LiveView for company management within the admin dashboard.

  This view displays a grid of companies owned by the current user and
  provides functionality to create new companies. It subscribes to
  real-time updates for companies via PubSub.
  """
  use Public, :live_view

  alias Core.{Companies, Subscriptions, Repo}
  alias Core.PubSub.DataSync
  alias Public.PageMeta
  import Public.Dashboard.Admin.CompanyHelpers

  @doc """
  Initializes the LiveView with companies data and subscriptions.

  Loads companies owned by the current user, sets up PubSub subscriptions
  for real-time updates, and determines the company creation limit based
  on the user's subscription plan.
  """
  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    if connected?(socket) do
      DataSync.subscribe("companies", current_user.id)
      DataSync.subscribe("companies", "all")
    end

    companies = Companies.list_companies_by_owner(current_user.id)
    subscription = if current_user.role == :super_admin do
      %{plan: %{features: %{"projects" => "Unlimited"}}}
    else
      Subscriptions.get_user_subscription(current_user.id)
    end

    can_create_company = Subscriptions.can_create_company?(current_user)

    {:ok,
     socket
     |> PageMeta.assign_metadata(
       title: "Company Management",
       description: "Manage your companies",
       url: "/dashboard/admin/companies"
     )
     |> assign(
       companies: companies,
       subscription: subscription,
       can_create_company: can_create_company,
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
    if company.owner_id == socket.assigns.current_user.id and not Enum.any?(socket.assigns.companies, &(&1.id == company.id)) do
      company = Repo.preload(company, [employees: [:profile]])
      {:noreply, update(socket, :companies, fn companies -> [company | companies] end)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:updated, %{type: :company, company: company}}, socket) do
    if company.owner_id == socket.assigns.current_user.id do
      company = Repo.preload(company, [employees: [:profile]])
      {:noreply,
       update(socket, :companies, fn companies ->
         Enum.map(companies, fn c -> if c.id == company.id, do: company, else: c end)
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted, %{type: :company, id: company_id}}, socket) do
    {:noreply,
     update(socket, :companies, fn companies ->
       Enum.reject(companies, &(&1.id == company_id))
     end)}
  end

  @impl true
  def handle_event("show_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_company_modal, true)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :show_create_company_modal, false)}
  end

  def handle_event("create_company", params, socket) do
    case handle_create_company(socket, params) do
      {:noreply, socket_after_create} ->
        if get_in(socket_after_create.assigns, [:flash, :error]) == nil do
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
      <div class="mb-6">
        <h1 class="text-3xl font-bold text-base-content">Companies</h1>
        <p class="text-base-content/70 mt-1">View all companies that are owned by you</p>
      </div>

      <div class="mt-6">
        <div class="flex justify-between items-center mb-4">
          <h2 class="text-xl font-semibold text-base-content">Your Companies</h2>
          <%= if @can_create_company do %>
            <button class="btn btn-primary" phx-click="show_create_modal">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
              </svg>
              Create Company
            </button>
          <% end %>
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
            ></textarea>
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
end
