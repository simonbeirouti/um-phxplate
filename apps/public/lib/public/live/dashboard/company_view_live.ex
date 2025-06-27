defmodule Public.Dashboard.Company.CompanyViewLive do
  @moduledoc """
  LiveView for detailed company information display.

  This view provides a detailed view of a company for users who have access
  to it (either as an owner, employee, or super admin). It displays company
  information, employee details, and allows for bookmarking functionality.
  It subscribes to real-time updates for companies, employees, and bookmarks.
  """
  use Public, :live_view
  alias Core.{Companies, Bookmarks}
  alias Core.PubSub.DataSync
  alias Public.PageMeta

  @doc """
  Initializes the LiveView with company data and subscription setup.

  Sets up PubSub subscriptions for the company, its employees, and the
  user's bookmarks. Loads the company data if the user has access rights,
  otherwise redirects to the dashboard.
  """
  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to company updates
      DataSync.subscribe("companies", id)
      # Subscribe to employee updates for this company
      DataSync.subscribe("employees", id)
      # Subscribe to user-specific bookmark updates
      DataSync.subscribe("bookmarks", socket.assigns.current_user.id)
    end

    case get_company_data(id, socket.assigns.current_user) do
      {:ok, data} ->
        {:ok,
         socket
         |> PageMeta.assign_metadata(
           title: data.company.name,
           description: "View company information",
           url: "/dashboard/companies/#{data.company.id}"
         )
         |> assign(:company, data.company)
         |> assign(:is_bookmarked, data.is_bookmarked)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have access to this company")
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    # Update current path for breadcrumbs
    uri = URI.parse(url)
    {:noreply, assign(socket, :current_path, uri.path)}
  end

  @impl true
  def handle_info({:updated, %{type: :company, company: company}}, socket) do
    # Only update if user still has access
    case get_company_data(company.id, socket.assigns.current_user) do
      {:ok, data} ->
        {:noreply, assign(socket, :company, data.company)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You no longer have access to this company")
         |> redirect(to: ~p"/dashboard")}
    end
  end

  def handle_info({:deleted, %{type: :company}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "This company has been deleted.")
     |> redirect(to: ~p"/dashboard")}
  end

  def handle_info({:created, %{type: :bookmark, bookmark: bookmark}}, socket) do
    if bookmark.company_id == socket.assigns.company.id do
      {:noreply, assign(socket, :is_bookmarked, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted, %{type: :bookmark}}, socket) do
    # Recheck bookmark status
    is_bookmarked =
      Bookmarks.bookmarked?(
        socket.assigns.current_user.id,
        socket.assigns.company.id
      )

    {:noreply, assign(socket, :is_bookmarked, is_bookmarked)}
  end

  def handle_info({:deleted, %{type: :employee, id: employee_id}}, socket) do
    # If the deleted employee is the current user, redirect them
    current_user_employee =
      Enum.find(
        socket.assigns.company.employees,
        &(&1.email == socket.assigns.current_user.email)
      )

    if current_user_employee && current_user_employee.id == employee_id do
      {:noreply,
       socket
       |> put_flash(:error, "You have been removed from this company.")
       |> redirect(to: ~p"/dashboard")}
    else
      # Otherwise, just update the company data
      case get_company_data(socket.assigns.company.id, socket.assigns.current_user) do
        {:ok, data} ->
          {:noreply, assign(socket, :company, data.company)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "You no longer have access to this company")
           |> redirect(to: ~p"/dashboard")}
      end
    end
  end

  @impl true
  def handle_event("toggle_bookmark", _params, socket) do
    current_user_id = socket.assigns.current_user.id
    company_id = socket.assigns.company.id

    if socket.assigns.is_bookmarked do
      bookmark = Bookmarks.get_bookmark(current_user_id, company_id)

      case Bookmarks.delete_bookmark(bookmark) do
        {:ok, _} -> {:noreply, assign(socket, :is_bookmarked, false)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not remove bookmark")}
      end
    else
      case Bookmarks.create_bookmark(%{user_id: current_user_id, company_id: company_id}) do
        {:ok, _} -> {:noreply, assign(socket, :is_bookmarked, true)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create bookmark")}
      end
    end
  end

  defp get_company_data(id, user) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> get_company_data(id, user)
      _ -> {:error, :invalid_id}
    end
  end

  defp get_company_data(id, user) when is_integer(id) do
    with %Companies.Company{} = company <- Companies.get_company!(id),
         true <- has_access?(company, user) do
      is_bookmarked = Bookmarks.bookmarked?(user.id, company.id)
      {:ok, %{company: company, is_bookmarked: is_bookmarked}}
    else
      _ -> {:error, :not_found}
    end
  end

  defp has_access?(company, user) do
    cond do
      # User owns the company
      company.owner_id == user.id -> true
      # User is an employee
      Enum.any?(company.employees, &(&1.email == user.email)) -> true
      # User is a super admin
      user.role == :super_admin -> true
      # No access
      true -> false
    end
  end

  @doc """
  Renders the company view with company details and employee information.

  Displays company metadata, contact information, and a list of employees.
  Includes a bookmark button for quickly saving the company for future access.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <.header>
          {@company.name}
          <:subtitle>Company Information</:subtitle>
        </.header>
        <button
          phx-click="toggle_bookmark"
          class="inline-flex items-center px-4 py-2 border rounded-md shadow-sm text-sm font-medium"
        >
          <%= if @is_bookmarked do %>
            <.icon name="hero-bookmark-solid" class="h-5 w-5" />
          <% else %>
            <.icon name="hero-bookmark" class="h-5 w-5" />
          <% end %>
        </button>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div class="space-y-2">
          <label class="text-sm font-medium">Name</label>
          <div class="text-gray-700">{@company.name}</div>
        </div>

        <div class="space-y-2">
          <label class="text-sm font-medium">Description</label>
          <div class="text-gray-700">{@company.description}</div>
        </div>

        <div class="space-y-2">
          <label class="text-sm font-medium">Address</label>
          <div class="text-gray-700">{@company.address}</div>
        </div>

        <div class="space-y-2">
          <label class="text-sm font-medium">Phone</label>
          <div class="text-gray-700">{@company.phone}</div>
        </div>

        <div class="space-y-2">
          <label class="text-sm font-medium">Email</label>
          <div class="text-gray-700">{@company.email}</div>
        </div>

        <div class="space-y-2">
          <label class="text-sm font-medium">Website</label>
          <div class="text-gray-700">
            <.link href={@company.website} target="_blank" class="text-primary hover:underline">
              {@company.website}
            </.link>
          </div>
        </div>
      </div>

      <.header class="mt-8">
        Employees
        <:subtitle>List of all employees in the company</:subtitle>
      </.header>

      <div class="divide-y divide-gray-200">
        <%= for employee <- @company.employees do %>
          <div class="py-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <div class="flex-shrink-0">
                  <img
                    src={
                      if employee.profile,
                        do: employee.profile.avatar_url || "/images/default-avatar.svg",
                        else: "/images/default-avatar.svg"
                    }
                    alt={employee.profile.first_name}
                    class="w-10 h-10 rounded-full bg-gray-100"
                  />
                </div>
                <div>
                  <div class="text-sm font-medium text-gray-900">
                    {employee.profile.first_name} {employee.profile.last_name}
                  </div>
                  <div class="text-sm text-gray-500">
                    {employee.email}
                  </div>
                </div>
              </div>
              <div class="text-right">
                <div class="text-sm text-gray-900">
                  {employee.position || "-"}
                </div>
                <div class="text-sm text-gray-500">
                  {employee.department || "-"}
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
