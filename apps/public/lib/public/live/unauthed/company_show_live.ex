defmodule Public.CompanyShowLive do
  @moduledoc """
  LiveView for displaying detailed information about a single company.

  This view shows comprehensive information about a specific company, including
  its name, description, logo, contact information, and address. It also provides
  functionality for authenticated users to bookmark companies for later reference.
  The view subscribes to real-time updates for the specific company being viewed.
  """
  use Public, :live_view

  alias Core.Companies
  alias Core.Bookmarks
  alias Core.PubSub.DataSync
  alias Public.PageMeta

  @doc """
  Initializes the LiveView with company details and bookmark status.

  Fetches the company by ID and checks if the current user has bookmarked it.
  Sets up a PubSub subscription for real-time updates to the specific company.
  Sets page metadata based on the company's information.
  """
  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("companies", id)
    end

    company = Companies.get_company!(id)

    bookmarked =
      if socket.assigns.current_user do
        Bookmarks.bookmarked?(socket.assigns.current_user.id, company.id)
      else
        false
      end

    {:ok,
     socket
     |> PageMeta.assign_metadata(
       title: company.name,
       description: company.description,
       image: company.logo,
       url: "/companies/#{company.id}"
     )
     |> assign(company: company, bookmarked: bookmarked)
    }
  end

  @impl true
  def handle_info({:updated, %{type: :company, company: company}}, socket) do
    {:noreply, assign(socket, :company, company)}
  end

  def handle_info({:deleted, %{type: :company}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "This company has been deleted.")
     |> redirect(to: ~p"/companies")}
  end

  @doc """
  Renders the company detail view with comprehensive information.

  Displays the company logo, name, description, and contact information.
  For authenticated users, provides options to bookmark or unbookmark the company.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4">
      <div class="my-6">
        <.link navigate={~p"/companies"}>
          <button class="btn btn-outline">
            ← Back to Companies
          </button>
        </.link>
      </div>
      <div class="card bg-base-100 shadow-lg">
        <figure class="relative h-64 sm:h-96 bg-base-200">
          <%= if @company.logo do %>
            <img src={@company.logo} alt={@company.name} class="h-full w-full object-cover" />
          <% else %>
            <div class="absolute inset-0 flex items-center justify-center">
              <div class="text-6xl font-bold text-base-content/50">
                <%= String.first(@company.name) %>
              </div>
            </div>
          <% end %>
        </figure>

        <div class="card-body">
          <div class="flex items-center justify-between">
            <h1 class="card-title text-3xl text-base-content"><%= @company.name %></h1>
            <%= if @current_user do %>
              <button
                phx-click={if @bookmarked, do: "unbookmark", else: "bookmark"}
                class={["btn btn-ghost", if(@bookmarked, do: "btn-primary", else: "")]}>
                <%= if @bookmarked do %>
                  <.icon name="hero-bookmark-solid" class="h-5 w-5" />
                <% else %>
                  <.icon name="hero-bookmark" class="h-5 w-5" />
                <% end %>
              </button>
            <% end %>
          </div>
          <%= if @company.description do %>
            <p class="text-base-content/80 mt-4"><%= @company.description %></p>
          <% end %>
        </div>

        <div class="divider mx-6"></div>

        <div class="card-body pt-0">
          <dl class="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2">
            <%= if @company.website do %>
              <div class="sm:col-span-1">
                <dt class="text-sm font-medium text-base-content/60">Website</dt>
                <dd class="mt-1">
                  <a href={@company.website} target="_blank" class="link link-primary">
                    <%= @company.website %>
                  </a>
                </dd>
              </div>
            <% end %>

            <%= if @company.email do %>
              <div class="sm:col-span-1">
                <dt class="text-sm font-medium text-base-content/60">Email</dt>
                <dd class="mt-1">
                  <a href={"mailto:#{@company.email}"} class="link link-primary">
                    <%= @company.email %>
                  </a>
                </dd>
              </div>
            <% end %>

            <%= if @company.phone do %>
              <div class="sm:col-span-1">
                <dt class="text-sm font-medium text-base-content/60">Phone</dt>
                <dd class="mt-1">
                  <a href={"tel:#{@company.phone}"} class="link link-primary">
                    <%= @company.phone %>
                  </a>
                </dd>
              </div>
            <% end %>

            <%= if @company.address do %>
              <div class="sm:col-span-1">
                <dt class="text-sm font-medium text-base-content/60">Address</dt>
                <dd class="mt-1 text-base-content"><%= @company.address %></dd>
              </div>
            <% end %>
          </dl>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("bookmark", _params, socket) do
    case Bookmarks.create_bookmark(%{
           user_id: socket.assigns.current_user.id,
           company_id: socket.assigns.company.id
         }) do
      {:ok, _bookmark} ->
        {:noreply,
         socket
         |> assign(:bookmarked, true)
         |> put_flash(:info, "Company bookmarked successfully.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, error_to_string(changeset))}
    end
  end

  @impl true
  def handle_event("unbookmark", _params, socket) do
    bookmark = Bookmarks.get_bookmark(socket.assigns.current_user.id, socket.assigns.company.id)

    case Bookmarks.delete_bookmark(bookmark) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:bookmarked, false)
         |> put_flash(:info, "Bookmark removed successfully.")}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not remove bookmark.")}
    end
  end

  defp error_to_string(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {_key, value} -> value end)
    |> List.flatten()
    |> Enum.join(", ")
  end
end
