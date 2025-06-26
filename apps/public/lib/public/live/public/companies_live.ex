defmodule Public.CompaniesLive do
  @moduledoc """
  LiveView for displaying a list of companies.

  This view fetches and displays all companies in a grid layout with basic information
  and thumbnails. It subscribes to real-time updates for company creation, updates,
  and deletions through PubSub, allowing the list to stay current without page refresh.
  """
  use Public, :live_view

  alias Core.Companies
  alias Core.PubSub.DataSync
  alias Public.PageMeta

  @doc """
  Initializes the LiveView with a list of companies and sets up PubSub subscription.

  Subscribes to company updates if the socket is connected and fetches the initial
  company list. Sets page metadata with appropriate title and description.
  """
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("companies", "all")
    end

    companies = Companies.list_companies()

    {:ok,
     socket
     |> PageMeta.assign_metadata(
       title: "Companies",
       description: "Discover amazing companies",
       url: "/companies"
     )
     |> assign(companies: companies)
    }
  end

  @impl true
  def handle_info({:created, %{type: :company, company: company}}, socket) do
    {:noreply, update(socket, :companies, fn companies -> [company | companies] end)}
  end

  def handle_info({:updated, %{type: :company, company: company}}, socket) do
    {:noreply,
     update(socket, :companies, fn companies ->
       Enum.map(companies, fn c -> if c.id == company.id, do: company, else: c end)
     end)}
  end

  def handle_info({:deleted, %{type: :company, id: company_id}}, socket) do
    {:noreply,
     update(socket, :companies, fn companies ->
       Enum.reject(companies, &(&1.id == company_id))
     end)}
  end

  @doc """
  Renders the companies list view with a grid of company cards.

  Each company card displays a logo (or initial if no logo), name, and description.
  Cards link to individual company pages.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <.header_section title="Companies" subtitle="Discover amazing companies" />
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <%= for company <- @companies do %>
          <.link navigate={~p"/companies/#{company.id}"} class="block">
            <div class="bg-white overflow-hidden shadow rounded-lg hover:shadow-lg transition-shadow duration-200">
              <div class="h-48 bg-gray-200 flex items-center justify-center">
                <%= if company.logo do %>
                  <img src={company.logo} alt={company.name} class="h-full w-full object-cover" />
                <% else %>
                  <div class="text-4xl font-bold text-gray-400">
                    <%= String.first(company.name) %>
                  </div>
                <% end %>
              </div>
              <div class="p-6">
                <h3 class="text-xl font-semibold text-gray-900"><%= company.name %></h3>
                <%= if company.description do %>
                  <p class="mt-2 text-gray-600 line-clamp-2"><%= company.description %></p>
                <% end %>
              </div>
            </div>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end
end
