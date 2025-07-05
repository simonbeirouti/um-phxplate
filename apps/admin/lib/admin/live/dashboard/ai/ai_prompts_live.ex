defmodule Admin.AiPromptsLive do
  @moduledoc """
  LiveView for managing AI prompts.

  This view provides functionality for super admins to create, edit, and manage
  AI prompts with categorization, search, and pagination.
  """
  use Admin, :live_view
  alias Core.AI
  alias Core.AI.{Prompt, Models}
  alias Admin.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:show_drawer, false)
     |> assign(:drawer_mode, "create")
     |> assign(:selected_item, nil)
     |> assign(:selected_model, Models.default_model_display_name())
     |> assign(:category_filter, "all")
     |> assign(:page, 1)
     |> assign(:per_page, 12)
     |> assign(:prompts, [])
     |> assign(:total_pages, 1)
     |> assign(:total_count, 0)
     |> assign(:screen_mode, "dialog")
     |> assign(:delete_prompt_id, nil)
     |> load_prompts()
     |> PageMeta.assign_metadata(
       title: "AI Prompts",
       description: "Manage AI prompts",
       url: "/dashboard/super_admin/ai-prompts"
     )}
  end

  @impl true
  def handle_params(params, url, socket) do
    uri = URI.parse(url)
    socket = update(socket, :layout_data, &Map.put(&1, :current_path, uri.path))

    page = String.to_integer(Map.get(params, "page", "1"))

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_prompts()}
  end

  @impl true
  def handle_event("select_model", %{"model" => model}, socket) do
    {:noreply, assign(socket, :selected_model, model)}
  end

  @impl true
  def handle_event("set_screen_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :screen_mode, mode)}
  end

  @impl true
  def handle_event("form_change", %{"prompt" => prompt_params}, socket) do
    changeset =
      case socket.assigns.selected_item do
        %Ecto.Changeset{data: data} -> Prompt.changeset(data, prompt_params)
        item -> Prompt.changeset(item, prompt_params)
      end

    {:noreply, assign(socket, :selected_item, changeset)}
  end

  @impl true
  def handle_event("category_changed", %{"value" => category}, socket) do
    # Update the changeset with the selected category
    current_data =
      case socket.assigns.selected_item do
        %Ecto.Changeset{data: data, changes: changes} ->
          Map.merge(data, changes)

        item ->
          item
      end

    changeset = Prompt.changeset(current_data, %{"category" => category})

    {:noreply, assign(socket, :selected_item, changeset)}
  end

  @impl true
  def handle_event("status_changed", %{"value" => value}, socket) do
    # Convert string to boolean
    is_active =
      case value do
        "true" -> true
        "false" -> false
        _ -> true
      end

    # Update the changeset with the selected status
    current_data =
      case socket.assigns.selected_item do
        %Ecto.Changeset{data: data, changes: changes} ->
          Map.merge(data, changes)

        item ->
          item
      end

    changeset = Prompt.changeset(current_data, %{"is_active" => is_active})

    {:noreply, assign(socket, :selected_item, changeset)}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:category_filter, category)
     |> assign(:page, 1)
     |> load_prompts()}
  end

  @impl true
  def handle_event("create_prompt", _params, socket) do
    # Pre-populate category based on current filter and set default active status
    initial_attrs =
      case socket.assigns.category_filter do
        "all" -> %{"is_active" => true}
        category -> %{"category" => category, "is_active" => true}
      end

    initial_prompt = %Prompt{}
    changeset = Prompt.changeset(initial_prompt, initial_attrs)

    {:noreply,
     socket
     |> assign(:show_drawer, true)
     |> assign(:drawer_mode, "create_prompt")
     |> assign(:selected_item, changeset)}
  end

  @impl true
  def handle_event("view_prompt", %{"id" => id}, socket) do
    prompt = AI.get_prompt_with_creator(id)

    {:noreply,
     socket
     |> assign(:show_drawer, true)
     |> assign(:drawer_mode, "view_prompt")
     |> assign(:selected_item, prompt)}
  end

  @impl true
  def handle_event("edit_prompt", %{"id" => id}, socket) do
    prompt = AI.get_prompt_with_creator(id)

    {:noreply,
     socket
     |> assign(:show_drawer, true)
     |> assign(:drawer_mode, "edit_prompt")
     |> assign(:selected_item, prompt)}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_drawer, false)
     |> assign(:selected_item, nil)}
  end

  @impl true
  def handle_event("save_prompt", %{"prompt" => prompt_params}, socket) do
    current_user = socket.assigns.current_user
    prompt_params = Map.put(prompt_params, "created_by", current_user.id)

    case socket.assigns.drawer_mode do
      "create_prompt" ->
        case AI.create_prompt(prompt_params) do
          {:ok, _prompt} ->
            {:noreply,
             socket
             |> put_flash(:info, "Prompt created successfully")
             |> assign(:show_drawer, false)
             |> load_prompts()}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:selected_item, %Prompt{} |> Prompt.changeset(prompt_params))
             |> put_flash(:error, "Failed to create prompt")}
        end

      "edit_prompt" ->
        case AI.update_prompt(socket.assigns.selected_item, prompt_params) do
          {:ok, _prompt} ->
            {:noreply,
             socket
             |> put_flash(:info, "Prompt updated successfully")
             |> assign(:show_drawer, false)
             |> load_prompts()}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:selected_item, changeset)
             |> put_flash(:error, "Failed to update prompt")}
        end
    end
  end

  @impl true
  def handle_event("prepare_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_prompt_id, String.to_integer(id))}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_prompt_id, nil)}
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    prompt = AI.get_prompt(id)

    case AI.delete_prompt(prompt) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:delete_prompt_id, nil)
         |> put_flash(:info, "Prompt deleted successfully")
         |> load_prompts()}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:delete_prompt_id, nil)
         |> put_flash(:error, "Failed to delete prompt")}
    end
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_prompts()
     |> push_patch(to: ~p"/dashboard/super_admin/ai-prompts?page=#{page}")}
  end

  defp load_prompts(socket) do
    opts = [
      category: socket.assigns.category_filter
    ]

    result = AI.list_prompts(socket.assigns.page, socket.assigns.per_page, opts)

    socket
    |> assign(:prompts, result.prompts)
    |> assign(:total_pages, result.total_pages)
    |> assign(:total_count, result.total_count)
  rescue
    # Handle case where tables don't exist yet
    _ ->
      socket
      |> assign(:prompts, [])
      |> assign(:total_pages, 1)
      |> assign(:total_count, 0)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        AI Prompts
        <:subtitle>Manage AI prompts</:subtitle>
        <:actions>
          <div class="flex items-center gap-3">
            <form phx-change="filter_category" class="w-auto">
              <select id="category-filter" name="category" class="select select-bordered w-48" phx-change="filter_category">
                <option value="all" selected={@category_filter == "all"}>All Categories</option>
                <%= for category <- Prompt.categories() do %>
                  <option value={category} selected={@category_filter == category}>{Prompt.format_category(category)}</option>
                <% end %>
              </select>
            </form>
            <button phx-click="create_prompt" class="btn btn-neutral">
              <.icon name="hero-plus" class="h-4 w-4 mr-2 hidden sm:inline" />
              <span class="hidden sm:inline">New Prompt</span>
              <.icon name="hero-plus" class="h-4 w-4 sm:hidden" />
            </button>
          </div>
        </:actions>
      </.header>



      <div class="mt-6">
        <%= if Enum.empty?(@prompts) do %>
          <.empty_state
            title="No prompts found"
            description="Get started by creating your first AI prompt."
            action_text="Create Prompt"
            action_event="create_prompt"
          />
        <% else %>
          <.prompts_grid prompts={@prompts} delete_prompt_id={@delete_prompt_id} />
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
                class={["join-item", "btn", page_num == @page && "btn-active"]}
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

      <dialog id="ai-prompts-modal" class={["modal", @show_drawer && "modal-open"]}>
        <div class="modal-box">
          <h3 class="font-bold text-lg">{get_drawer_title(@drawer_mode)}</h3>
          <p class="py-4">{get_drawer_description(@drawer_mode)}</p>
          <%= case @drawer_mode do %>
            <% "view_prompt" -> %>
              <.prompt_view item={@selected_item} />
            <% mode when mode in ["create_prompt", "edit_prompt"] -> %>
              <.prompt_form item={@selected_item} mode={@drawer_mode} />
          <% end %>
        </div>
        <form method="dialog" class="modal-backdrop" phx-click="close_drawer">
          <button>close</button>
        </form>
      </dialog>
    </div>
    """
  end

  defp get_drawer_title("create_prompt"), do: "Create New Prompt"
  defp get_drawer_title("edit_prompt"), do: "Edit Prompt"
  defp get_drawer_title("view_prompt"), do: "View Prompt"

  defp get_drawer_description("create_prompt"), do: "Create a new AI prompt for your collection"
  defp get_drawer_description("edit_prompt"), do: "Edit the selected AI prompt"
  defp get_drawer_description("view_prompt"), do: "View prompt details and content"

  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <div class="mx-auto h-12 w-12 text-gray-400">
        <.icon name="hero-chat-bubble-bottom-center-text" class="h-12 w-12" />
      </div>
      <h3 class="mt-2 text-sm font-medium text-gray-900">{@title}</h3>
      <p class="mt-1 text-sm text-gray-500">{@description}</p>
      <div class="mt-6">
        <button phx-click={@action_event} class="btn btn-neutral">
          <.icon name="hero-plus" class="h-4 w-4 mr-2" />
          {@action_text}
        </button>
      </div>
    </div>
    """
  end

  defp prompts_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      <%= for prompt <- @prompts do %>
        <div class="bg-white rounded-lg border border-gray-200 shadow-sm hover:shadow-md transition-shadow duration-200">
          <div class="p-6">
            <div class="flex items-start justify-between mb-3">
              <h3 class="text-lg font-semibold text-gray-900 truncate pr-2">
                {prompt.name}
              </h3>
              <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-gray-100 text-gray-800 whitespace-nowrap">
                {Prompt.format_category(prompt.category)}
              </span>
            </div>

            <%= if prompt.description do %>
              <p class="text-sm text-gray-600 mb-4 line-clamp-3">
                {String.slice(prompt.description, 0, 250)}{if String.length(prompt.description) > 250,
                  do: "..."}
              </p>
            <% else %>
              <p class="text-sm text-gray-400 mb-4 italic">No description provided</p>
            <% end %>

            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-3">
                <span class={[
                  "inline-flex px-2 py-1 text-xs font-semibold rounded-full",
                  if(prompt.is_active,
                    do: "bg-green-100 text-green-800",
                    else: "bg-red-100 text-red-800"
                  )
                ]}>
                  {if prompt.is_active, do: "Active", else: "Inactive"}
                </span>
                <span class="text-xs text-gray-500">
                  {Calendar.strftime(prompt.inserted_at, "%b %d, %Y")}
                </span>
              </div>

              <div class="flex items-center space-x-1">
                <button class="btn btn-outline btn-sm" phx-click="view_prompt" phx-value-id={prompt.id}>
                  <.icon name="hero-eye" class="h-4 w-4" />
                </button>
                <button class="btn btn-outline btn-sm" phx-click="edit_prompt" phx-value-id={prompt.id}>
                  <.icon name="hero-pencil" class="h-4 w-4" />
                </button>
                <%= if @delete_prompt_id && @delete_prompt_id == prompt.id do %>
                  <button
                    class="btn btn-error btn-sm"
                    phx-click="confirm_delete"
                    phx-value-id={prompt.id}
                    title="Click to confirm deletion"
                  >
                    <.icon name="hero-check" class="h-4 w-4" />
                  </button>
                  <button
                    class="btn btn-outline btn-sm"
                    phx-click="cancel_delete"
                    title="Cancel deletion"
                  >
                    <.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                <% else %>
                  <button
                    class="btn btn-outline btn-sm"
                    phx-click="prepare_delete"
                    phx-value-id={prompt.id}
                    title="Delete prompt"
                  >
                    <.icon name="hero-trash" class="h-4 w-4" />
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp prompt_view(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-start justify-between">
        <div>
          <h2 class="text-xl font-semibold text-gray-900">{@item.name}</h2>
          <span class="inline-flex px-2 py-1 text-sm font-semibold rounded-full bg-gray-100 text-gray-800 mt-2">
            {Prompt.format_category(@item.category)}
          </span>
        </div>
        <span class={[
          "inline-flex px-3 py-1 text-sm font-semibold rounded-full",
          if(@item.is_active,
            do: "bg-green-100 text-green-800",
            else: "bg-red-100 text-red-800"
          )
        ]}>
          {if @item.is_active, do: "Active", else: "Inactive"}
        </span>
      </div>

      <%= if @item.description do %>
        <div>
          <h3 class="text-sm font-medium text-gray-900 mb-2">Description</h3>
          <p class="text-sm text-gray-600">{@item.description}</p>
        </div>
      <% end %>

      <div>
        <h3 class="text-sm font-medium text-gray-900 mb-2">Prompt Content</h3>
        <div class="bg-gray-50 rounded-lg p-4">
          <pre class="text-sm text-gray-800 whitespace-pre-wrap font-mono">{@item.content}</pre>
        </div>
      </div>

      <div>
        <h4 class="text-sm font-medium text-gray-900">Created</h4>
        <p class="text-sm text-gray-600">
          {Calendar.strftime(@item.inserted_at, "%B %d, %Y at %I:%M %p")}
        </p>
      </div>

      <div class="flex flex-col space-y-3 pt-4 border-t border-gray-200">
        <button phx-click="edit_prompt" phx-value-id={@item.id} class="btn btn-neutral w-full">
          <.icon name="hero-pencil" class="h-4 w-4 mr-2" /> Edit Prompt
        </button>
        <button class="btn btn-outline w-full" phx-click="close_drawer">Close</button>
      </div>
    </div>
    """
  end

  defp prompt_form(assigns) do
    changeset =
      case assigns.item do
        %Ecto.Changeset{} -> assigns.item
        item -> Prompt.changeset(item, %{})
      end

    assigns = assign(assigns, :changeset, changeset)

    ~H"""
    <.form :let={f} for={@changeset} phx-submit="save_prompt" phx-change="form_change">
      <div class="space-y-4">
        <div>
          <label for={f[:name].id} class="label"><span class="label-text">Name</span></label>
          <input id={f[:name].id} name={f[:name].name} value={f[:name].value} type="text" placeholder="Enter prompt name" class="input input-bordered w-full" required />
        </div>
        <div>
          <label for={f[:description].id} class="label"><span class="label-text">Description</span></label>
          <textarea id={f[:description].id} name={f[:description].name} value={f[:description].value} class="textarea textarea-bordered w-full text-base" placeholder="Enter prompt description"></textarea>
        </div>

        <div>
          <label class="label"><span class="label-text">Category</span></label>
          <div class="mb-2 w-full">
            <% current_category =
              case @changeset do
                %Ecto.Changeset{} ->
                  Ecto.Changeset.get_field(@changeset, :category) || "general"

                _ ->
                  "general"
              end %>
            <div class="join w-full flex justify-start flex-wrap gap-1">
              <%= for category <- Prompt.categories() do %>
                <input
                  type="radio"
                  name="prompt[category]"
                  class="join-item btn px-3 py-2"
                  value={category}
                  aria-label={Prompt.format_category(category)}
                  checked={current_category == category}
                  phx-change="category_changed"
                />
              <% end %>
            </div>
          </div>
        </div>

        <div>
          <label for={f[:content].id} class="label"><span class="label-text">Prompt Content</span></label>
          <textarea id={f[:content].id} name={f[:content].name} value={f[:content].value} class="textarea textarea-bordered w-full text-base" placeholder="Enter prompt content" required></textarea>
        </div>

        <div>
          <label class="label"><span class="label-text">Status</span></label>
          <div class="mb-2 w-full">
            <% current_status =
              case @changeset do
                %Ecto.Changeset{} ->
                  Ecto.Changeset.get_field(@changeset, :is_active)

                _ ->
                  true
              end %>
            <div class="join w-full flex justify-between">
              <input
                type="radio"
                name="prompt[is_active]"
                class="join-item btn flex-1"
                value="true"
                aria-label="Active"
                checked={current_status}
                phx-change="status_changed"
              />
              <input
                type="radio"
                name="prompt[is_active]"
                class="join-item btn flex-1"
                value="false"
                aria-label="Inactive"
                checked={not current_status}
                phx-change="status_changed"
              />
            </div>
          </div>
        </div>
      </div>

      <div class="mt-6 flex flex-col space-y-3">
        <button type="submit" class="btn btn-neutral w-full">
          {if @mode == "create_prompt", do: "Create Prompt", else: "Update Prompt"}
        </button>
        <button type="button" class="btn btn-outline w-full" phx-click="close_drawer">
          Cancel
        </button>
      </div>
    </.form>
    """
  end
end
