defmodule Admin.AiEvalsLive do
  @moduledoc """
  LiveView for managing AI evaluations.

  This view provides functionality for super admins to create, edit, and manage
  AI evaluations, as well as run evaluations against different models.
  """
  use Admin, :live_view
  alias Core.AI
  alias Core.AI.{Eval, Models}
  alias Admin.PageMeta
  import Admin.Components.{PromptSelector, ModelSelector}

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to eval updates for realtime functionality
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Core.PubSub, "ai_evals")
    end

    {:ok,
     socket
     |> assign(:show_drawer, false)
     |> assign(:drawer_mode, nil)
     |> assign(:selected_item, nil)
     |> assign(:available_models, Models.available_models())
     |> assign(:selected_model, Models.default_model_display_name())
     |> assign(:selected_prompt_name, "Default System")
     |> assign(:prompts, load_prompts())
     |> assign(:test_cases, [])
     |> assign(:status_filter, "All Status")
     |> assign(:page, 1)
     |> assign(:per_page, 10)
     |> assign(:evals, [])
     |> assign(:total_pages, 1)
     |> assign(:total_count, 0)
     |> assign(:screen_mode, "dialog")
     |> assign(:delete_eval_id, nil)
     |> assign(:show_advanced_settings, false)
     |> assign(:show_advanced_settings_form, false)
     |> assign(:max_tokens, 4000)
     |> assign(:max_tokens_active, false)
     |> assign(:temperature, 0.7)
     |> assign(:temperature_active, false)
     |> assign(:top_k, 5)
     |> assign(:top_k_active, false)
     |> assign(:top_p, 0.9)
     |> assign(:top_p_active, false)
     |> load_evals()
     |> PageMeta.assign_metadata(
       title: "AI Evaluations",
       description: "Manage AI evaluations",
       url: "/dashboard/ai-evals"
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_evals()}
  end

  @impl true
  def handle_event("select_model", %{"model" => model}, socket) do
    {:noreply, assign(socket, :selected_model, model)}
  end

  @impl true
  def handle_event("create_eval", _params, socket) do
    # Create a changeset with default values for a new evaluation
    changeset = Eval.changeset(%Eval{}, %{"is_active" => true})

    {:noreply,
     socket
     |> assign(:show_drawer, true)
     |> assign(:drawer_mode, "create_eval")
     |> assign(:selected_item, changeset)
     |> assign(:test_cases, [%{id: generate_temp_id(), test_case: "", expected_output: ""}])}
  end

  @impl true
  def handle_event("edit_eval", %{"id" => id}, socket) do
    eval = AI.get_eval_with_creator(id)

    # Convert existing test cases and expected outputs to the new format
    test_cases = convert_maps_to_test_cases(eval.test_cases, eval.expected_outputs)

    {:noreply,
     socket
     |> assign(:show_drawer, true)
     |> assign(:drawer_mode, "edit_eval")
     |> assign(:selected_item, eval)
     |> assign(:test_cases, test_cases)}
  end

  @impl true
  def handle_event("run_eval", %{"id" => id}, socket) do
    eval = AI.get_eval_with_creator(id)

    {:noreply,
     socket
     |> assign(:show_drawer, true)
     |> assign(:drawer_mode, "run_eval")
     |> assign(:selected_item, eval)}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_drawer, false)
     |> assign(:selected_item, nil)
     |> assign(:drawer_mode, nil)
     |> assign(:test_cases, [])}
  end

  @impl true
  def handle_event("save_eval", %{"eval" => eval_params}, socket) do
    current_user = socket.assigns.current_user
    eval_params = Map.put(eval_params, "created_by", current_user.id)

    # Convert test cases to the expected format
    eval_params = convert_test_cases_to_maps(eval_params, socket.assigns.test_cases)

    case socket.assigns.drawer_mode do
      "create_eval" ->
        case AI.create_eval(eval_params) do
          {:ok, _eval} ->
            {:noreply,
             socket
             |> put_flash(:info, "Evaluation created successfully")
             |> assign(:show_drawer, false)
             |> load_evals()}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:selected_item, %Eval{} |> Eval.changeset(eval_params))
             |> put_flash(:error, "Failed to create evaluation")}
        end

      "edit_eval" ->
        case AI.update_eval(socket.assigns.selected_item, eval_params) do
          {:ok, _eval} ->
            {:noreply,
             socket
             |> put_flash(:info, "Evaluation updated successfully")
             |> assign(:show_drawer, false)
             |> load_evals()}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:selected_item, changeset)
             |> put_flash(:error, "Failed to update evaluation")}
        end
    end
  end

  @impl true
  def handle_event("prompt_changed", %{"prompt_name" => prompt_name}, socket) do
    {:noreply, assign(socket, :selected_prompt_name, prompt_name)}
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

    changeset = Eval.changeset(current_data, %{"is_active" => is_active})

    {:noreply, assign(socket, :selected_item, changeset)}
  end

  @impl true
  def handle_event("show_advanced_settings", _params, socket) do
    {:noreply, assign(socket, :show_advanced_settings, true)}
  end

  @impl true
  def handle_event("close_advanced_settings", _params, socket) do
    {:noreply, assign(socket, :show_advanced_settings, false)}
  end

  @impl true
  def handle_event("toggle_advanced_settings", _params, socket) do
    current_state = Map.get(socket.assigns, :show_advanced_settings_form, false)
    {:noreply, assign(socket, :show_advanced_settings_form, !current_state)}
  end

  @impl true
  def handle_event("update_advanced_settings", params, socket) do
    # Convert slider integer values back to appropriate ranges
    temperature =
      case params["temperature"] do
        nil -> 0.7
        temp_str -> String.to_integer(temp_str) / 100.0
      end

    top_p =
      case params["top_p"] do
        nil -> 0.9
        top_p_str -> String.to_integer(top_p_str) / 100.0
      end

    # Parse the new values
    max_tokens = String.to_integer(params["max_tokens"] || "4000")
    max_tokens_active = params["max_tokens_active"] == "true"
    temperature_active = params["temperature_active"] == "true"
    top_k = String.to_integer(params["top_k"] || "5")
    top_k_active = params["top_k_active"] == "true"
    top_p_active = params["top_p_active"] == "true"

    socket =
      socket
      |> assign(:max_tokens, max_tokens)
      |> assign(:max_tokens_active, max_tokens_active)
      |> assign(:temperature, temperature)
      |> assign(:temperature_active, temperature_active)
      |> assign(:top_k, top_k)
      |> assign(:top_k_active, top_k_active)
      |> assign(:top_p, top_p)
      |> assign(:top_p_active, top_p_active)

    {:noreply, socket}
  end

  @impl true
  def handle_event("execute_eval", _params, socket) do
    eval = socket.assigns.selected_item
    current_user = socket.assigns.current_user
    model_display_name = socket.assigns.selected_model

    # Convert prompt name to ID for the AI.run_evaluation function
    prompt_id =
      case socket.assigns.selected_prompt_name do
        "Default System" ->
          nil

        prompt_name ->
          case Enum.find(socket.assigns.prompts, &(&1.name == prompt_name)) do
            nil -> nil
            prompt -> prompt.id
          end
      end

    # Build advanced parameters
    advanced_params = %{
      max_tokens: if(socket.assigns.max_tokens_active, do: socket.assigns.max_tokens, else: nil),
      max_tokens_active: socket.assigns.max_tokens_active,
      temperature: if(socket.assigns.temperature_active, do: socket.assigns.temperature, else: nil),
      temperature_active: socket.assigns.temperature_active,
      top_k: if(socket.assigns.top_k_active, do: socket.assigns.top_k, else: nil),
      top_k_active: socket.assigns.top_k_active,
      top_p: if(socket.assigns.top_p_active, do: socket.assigns.top_p, else: nil),
      top_p_active: socket.assigns.top_p_active
    }

    # Store the display name in the database, evaluation logic will convert to API ID
    case AI.run_evaluation(eval.id, model_display_name, current_user.id, prompt_id, advanced_params) do
      {:ok, _eval_run} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Evaluation started successfully with #{model_display_name}"
         )
         |> assign(:show_drawer, false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to start evaluation")}
    end
  end

  @impl true
  def handle_event("prepare_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_eval_id, String.to_integer(id))}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_eval_id, nil)}
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    eval = AI.get_eval(id)

    case AI.delete_eval(eval) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:delete_eval_id, nil)
         |> put_flash(:info, "Evaluation deleted successfully")
         |> load_evals()}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:delete_eval_id, nil)
         |> put_flash(:error, "Failed to delete evaluation")}
    end
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_evals()
     |> push_patch(to: ~p"/dashboard/super_admin/ai-evals?page=#{page}")}
  end

  @impl true
  def handle_event("set_screen_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :screen_mode, mode)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 1)
     |> load_evals()}
  end

  @impl true
  def handle_event("toggle_status", %{"status_toggle" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 1)
     |> load_evals()}
  end

  @impl true
  def handle_event("add_test_case", _params, socket) do
    new_test_case = %{id: generate_temp_id(), test_case: "", expected_output: ""}
    updated_test_cases = socket.assigns.test_cases ++ [new_test_case]

    {:noreply, assign(socket, :test_cases, updated_test_cases)}
  end

  @impl true
  def handle_event("remove_test_case", %{"id" => id}, socket) do
    updated_test_cases = Enum.reject(socket.assigns.test_cases, &(&1.id == id))

    {:noreply, assign(socket, :test_cases, updated_test_cases)}
  end

  @impl true
  def handle_event("update_test_case", %{"id" => id, "field" => field, "value" => value}, socket) do
    updated_test_cases =
      Enum.map(socket.assigns.test_cases, fn test_case ->
        if test_case.id == id do
          Map.put(test_case, String.to_atom(field), value)
        else
          test_case
        end
      end)

    {:noreply, assign(socket, :test_cases, updated_test_cases)}
  end

  # Handle realtime updates from PubSub
  @impl true
  def handle_info({:eval_created, _eval}, socket) do
    # Reload evals when a new eval is created
    {:noreply, load_evals(socket)}
  end

  @impl true
  def handle_info({:eval_updated, _eval}, socket) do
    # Reload evals when an eval is updated
    {:noreply, load_evals(socket)}
  end

  @impl true
  def handle_info({:eval_deleted, _eval}, socket) do
    # Reload evals when an eval is deleted
    {:noreply, load_evals(socket)}
  end

  # Ignore other messages
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp load_evals(socket) do
    # Convert display text back to database values for status filter
    status_value =
      case socket.assigns.status_filter do
        "All Status" -> "all"
        "Active" -> "active"
        "Inactive" -> "inactive"
        other -> other
      end

    opts = [
      status: status_value
    ]

    result = AI.list_evals(socket.assigns.page, socket.assigns.per_page, opts)

    socket
    |> assign(:evals, result.evals)
    |> assign(:total_pages, result.total_pages)
    |> assign(:total_count, result.total_count)
  rescue
    # Handle case where tables don't exist yet
    _ ->
      socket
      |> assign(:evals, [])
      |> assign(:total_pages, 1)
      |> assign(:total_count, 0)
  end

  defp generate_temp_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp convert_test_cases_to_maps(params, test_cases) do
    # Filter out empty test cases
    valid_test_cases =
      Enum.reject(test_cases, fn tc ->
        String.trim(tc.test_case) == "" || String.trim(tc.expected_output) == ""
      end)

    test_cases_map =
      valid_test_cases
      |> Enum.with_index(1)
      |> Enum.map(fn {tc, index} -> {"test_#{index}", tc.test_case} end)
      |> Enum.into(%{})

    expected_outputs_map =
      valid_test_cases
      |> Enum.with_index(1)
      |> Enum.map(fn {tc, index} -> {"test_#{index}", tc.expected_output} end)
      |> Enum.into(%{})

    params
    |> Map.put("test_cases", test_cases_map)
    |> Map.put("expected_outputs", expected_outputs_map)
  end

  defp convert_maps_to_test_cases(test_cases_map, expected_outputs_map)
       when is_map(test_cases_map) and is_map(expected_outputs_map) do
    # Get all keys from both maps
    all_keys =
      MapSet.union(
        MapSet.new(Map.keys(test_cases_map)),
        MapSet.new(Map.keys(expected_outputs_map))
      )

    all_keys
    |> Enum.sort()
    |> Enum.map(fn key ->
      %{
        id: generate_temp_id(),
        test_case: Map.get(test_cases_map, key, ""),
        expected_output: Map.get(expected_outputs_map, key, "")
      }
    end)
    |> case do
      [] -> [%{id: generate_temp_id(), test_case: "", expected_output: ""}]
      test_cases -> test_cases
    end
  end

  defp convert_maps_to_test_cases(_, _) do
    [%{id: generate_temp_id(), test_case: "", expected_output: ""}]
  end

  defp load_prompts do
    try do
      AI.list_prompts()
    rescue
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        AI Evaluations
        <:subtitle>Manage AI evaluations and test suites</:subtitle>
        <:actions>
          <div class="flex items-center gap-3">
            <form phx-change="filter_status" class="w-auto">
              <select id="status-filter" name="status" class="select select-bordered w-32" phx-change="filter_status">
                <option selected={@status_filter == "All Status"}>All Status</option>
                <option value="Active" selected={@status_filter == "Active"}>Active</option>
                <option value="Inactive" selected={@status_filter == "Inactive"}>Inactive</option>
              </select>
            </form>
            <button phx-click="create_eval" class="btn btn-neutral">
              <.icon name="hero-plus" class="h-4 w-4 mr-2 hidden sm:inline" />
              <span class="hidden sm:inline">New Evaluation</span>
              <.icon name="hero-plus" class="h-4 w-4 sm:hidden" />
            </button>
          </div>
        </:actions>
      </.header>

      <div class="mt-6">
        <%= if Enum.empty?(@evals) do %>
          <.empty_state
            title="No evaluations found"
            description="Get started by creating your first AI evaluation."
            action_text="Create Evaluation"
            action_event="create_eval"
          />
        <% else %>
          <.evals_grid evals={@evals} delete_eval_id={@delete_eval_id} />
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

      <dialog id="ai-evals-modal" class={["modal", if(@show_drawer, do: "modal-open")]}>
        <div class="modal-box max-w-6xl max-h-[90vh] overflow-y-auto">
          <h3 class="font-bold text-lg">{get_drawer_title(@drawer_mode)}</h3>
          <p class="py-4">{get_drawer_description(@drawer_mode)}</p>
        <%= case @drawer_mode do %>
          <% mode when mode in ["create_eval", "edit_eval"] -> %>
            <.eval_form item={@selected_item} mode={@drawer_mode} test_cases={@test_cases} />
          <% "run_eval" -> %>
            <.eval_run_form
              item={@selected_item}
              selected_model={@selected_model}
              prompts={@prompts}
              selected_prompt_name={@selected_prompt_name}
              show_advanced_settings_form={@show_advanced_settings_form}
              max_tokens={@max_tokens}
              max_tokens_active={@max_tokens_active}
              temperature={@temperature}
              temperature_active={@temperature_active}
              top_k={@top_k}
              top_k_active={@top_k_active}
              top_p={@top_p}
              top_p_active={@top_p_active}
            />
          <% nil -> %>
            <%# Render nothing when drawer_mode is nil %>
        <% end %>
        </div>
        <form method="dialog" class="modal-backdrop" phx-click="close_drawer">
          <button>close</button>
        </form>
      </dialog>
    </div>

    <dialog id="advanced-settings-modal" class={["modal", if(@show_advanced_settings, do: "modal-open")]} class={["modal", if(@show_advanced_settings, do: "modal-open")]}>
      <div class="modal-box sm:max-w-6xl">
        <h3 class="font-bold text-lg">Advanced AI Parameters</h3>
        <p class="py-4">Configure advanced parameters for evaluation runs</p>
        <.advanced_settings_content
          max_tokens={@max_tokens}
          max_tokens_active={@max_tokens_active}
          temperature={@temperature}
          temperature_active={@temperature_active}
          top_k={@top_k}
          top_k_active={@top_k_active}
          top_p={@top_p}
          top_p_active={@top_p_active}
        />
      </div>
      <form method="dialog" class="modal-backdrop" phx-click="close_advanced_settings">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <div class="mx-auto h-12 w-12 text-base-content/40">
        <.icon name="hero-clipboard-document-check" class="h-12 w-12" />
      </div>
      <h3 class="mt-2 text-sm font-medium text-base-content">{@title}</h3>
      <p class="mt-1 text-sm text-base-content/70">{@description}</p>
      <div class="mt-6">
        <button phx-click={@action_event} class="btn btn-neutral">
          <.icon name="hero-plus" class="h-4 w-4 mr-2" />
          {@action_text}
        </button>
      </div>
    </div>
    """
  end

  defp evals_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      <%= for eval <- @evals do %>
        <div class="bg-base-100 rounded-lg border border-base-300 shadow-sm hover:shadow-md transition-shadow duration-200">
          <div class="p-6">
            <div class="flex items-start justify-between mb-4">
              <h3 class="text-lg font-semibold text-base-content truncate pr-2">
                {eval.name}
              </h3>
              <span class={[
                "badge",
                (if eval.is_active, do: "badge-success", else: "badge-ghost")
              ]}>
                {if eval.is_active, do: "Active", else: "Inactive"}
              </span>
            </div>

            <div class="mb-4 space-y-2">
              <p class="text-sm text-base-content/70">
                <strong>Test Cases:</strong> {map_size(eval.test_cases)}
              </p>
              <%= if eval.evaluation_criteria && String.trim(eval.evaluation_criteria) != "" do %>
                <p class="text-xs text-base-content/70 leading-relaxed">
                  {String.slice(eval.evaluation_criteria, 0, 250)}{if String.length(eval.evaluation_criteria) > 250, do: "..."}
                </p>
              <% end %>
            </div>

            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-2">
                <button class="btn btn-outline btn-sm" phx-click="run_eval" phx-value-id={eval.id}>
                  <.icon name="hero-play" class="h-4 w-4" />
                </button>
                <button class="btn btn-outline btn-sm" phx-click="edit_eval" phx-value-id={eval.id}>
                  <.icon name="hero-pencil" class="h-4 w-4" />
                </button>
              </div>

              <div class="flex items-center space-x-1">
                <%= if @delete_eval_id && @delete_eval_id == eval.id do %>
                  <button
                    class="btn btn-error btn-sm"
                    phx-click="confirm_delete"
                    phx-value-id={eval.id}
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
                    phx-value-id={eval.id}
                    title="Delete evaluation"
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

  defp eval_form(assigns) do
    changeset =
      case assigns.item do
        %Ecto.Changeset{} -> assigns.item
        item -> Eval.changeset(item, %{})
      end

    assigns = assign(assigns, :changeset, changeset)

    ~H"""
    <.form :let={f} for={@changeset} phx-submit="save_eval">
      <div class="space-y-4">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label for={f[:name].id} class="label">
              <span class="label-text">Name</span>
            </label>
            <input
              type="text"
              id={f[:name].id}
              name={f[:name].name}
              value={f[:name].value}
              class="input input-bordered w-full"
              placeholder="Enter evaluation name"
              required
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text">Status</span>
            </label>
            <div class="mt-2 w-full">
              <% current_status =
                case @changeset do
                  %Ecto.Changeset{} ->
                    Ecto.Changeset.get_field(@changeset, :is_active)

                  _ ->
                    true
                end %>
              <div class="join w-full">
                <input
                  class="join-item btn btn-sm"
                  type="radio"
                  name="eval[is_active]"
                  aria-label="Active"
                  value="true"
                  checked={current_status}
                  phx-change="status_changed"
                />
                <input
                  class="join-item btn btn-sm"
                  type="radio"
                  name="eval[is_active]"
                  aria-label="Inactive"
                  value="false"
                  checked={!current_status}
                  phx-change="status_changed"
                />
              </div>
            </div>
          </div>
        </div>

        <div>
          <div class="flex items-center justify-between mb-3">
            <label class="label">
              <span class="label-text">Test Cases</span>
            </label>
            <button type="button" class="btn btn-outline btn-sm" phx-click="add_test_case">
              <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Test Case
            </button>
          </div>

          <div class="space-y-4">
            <%= for {test_case, index} <- Enum.with_index(@test_cases) do %>
              <div class="border border-base-300 rounded-lg p-4 bg-base-200">
                <div class="flex items-center justify-between mb-3">
                  <h4 class="text-sm font-medium text-base-content">Test Case #{index + 1}</h4>
                  <%= if length(@test_cases) > 1 do %>
                    <button
                      type="button"
                      class="btn btn-ghost btn-sm"
                      phx-click="remove_test_case"
                      phx-value-id={test_case.id}
                    >
                      <.icon name="hero-trash" class="h-4 w-4" />
                    </button>
                  <% end %>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label class="label">
                      <span class="label-text">Test Input</span>
                    </label>
                    <textarea
                      name={"test_case_#{test_case.id}"}
                      value={test_case.test_case}
                      phx-blur="update_test_case"
                      phx-value-id={test_case.id}
                      phx-value-field="test_case"
                      class="textarea textarea-bordered w-full"
                      placeholder="Enter the test input/question..."
                    ></textarea>
                  </div>
                  <div>
                    <label class="label">
                      <span class="label-text">Expected Output</span>
                    </label>
                    <textarea
                      name={"expected_output_#{test_case.id}"}
                      value={test_case.expected_output}
                      phx-blur="update_test_case"
                      phx-value-id={test_case.id}
                      phx-value-field="expected_output"
                      class="textarea textarea-bordered w-full"
                      placeholder="Enter the expected response..."
                    ></textarea>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div>
          <label for={f[:evaluation_criteria].id} class="label">
            <span class="label-text">Evaluation Criteria</span>
          </label>
          <textarea
            id={f[:evaluation_criteria].id}
            name={f[:evaluation_criteria].name}
            value={f[:evaluation_criteria].value}
            class="textarea textarea-bordered w-full text-base"
            placeholder="Enter evaluation criteria"
            required
          ></textarea>
        </div>
      </div>

      <div class="mt-6 flex flex-col space-y-3">
        <button type="submit" class="btn btn-neutral w-full">
          {if @mode == "create_eval", do: "Create Evaluation", else: "Update Evaluation"}
        </button>
        <button type="button" class="btn btn-outline w-full" phx-click="close_drawer">
          Cancel
        </button>
      </div>
    </.form>
    """
  end

  defp eval_run_form(assigns) do
    ~H"""
    <%= if @item do %>
      <div class="space-y-4">
        <div>
          <h3 class="text-lg font-medium">{@item.name}</h3>
          <p class="text-sm text-base-content/70">{@item.evaluation_criteria}</p>
        </div>

        <div>
          <h4 class="text-sm font-medium text-base-content mb-3">
            Test Cases ({map_size(@item.test_cases)})
          </h4>
          <div class="space-y-3">
            <%= for {key, test_case} <- @item.test_cases do %>
              <% expected_output = Map.get(@item.expected_outputs, key, "") %>
              <div class="border border-base-300 rounded-lg p-3 bg-base-200">
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                  <div>
                    <label class="label">
                      <span class="label-text">Test Input</span>
                    </label>
                    <div class="mt-1 p-2 bg-base-100 border border-base-300 rounded text-sm">
                      {test_case}
                    </div>
                  </div>
                  <div>
                    <label class="label">
                      <span class="label-text">Expected Output</span>
                    </label>
                    <div class="mt-1 p-2 bg-base-100 border border-base-300 rounded text-sm">
                      {expected_output}
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label class="label">
              <span class="label-text">Model</span>
            </label>
            <.model_selector
              selected_model={@selected_model}
              on_change="select_model"
              class="w-full"
              side="top"
              id="eval-model-selector"
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text">Prompt</span>
            </label>
            <.prompt_selector
              available_prompts={@prompts}
              selected_prompt={@selected_prompt_name}
              on_change="prompt_changed"
              class="w-full"
              side="top"
              id="eval-prompt-selector"
            />
          </div>
        </div>

        <div class="flex items-center justify-between">
          <label class="label">
            <span class="label-text">Advanced Parameters</span>
          </label>
          <button
            type="button"
            class="btn btn-outline btn-sm"
            phx-click="toggle_advanced_settings"
          >
            <.icon name="hero-cog" class="h-4 w-4 mr-1" />
            <%= if Map.get(assigns, :show_advanced_settings_form, false), do: "Hide", else: "Configure" %>
          </button>
        </div>

        <%= if Map.get(assigns, :show_advanced_settings_form, false) do %>
          <div class="border border-base-300 rounded-lg p-4 bg-base-200 space-y-6">
            <.form
              for={%{}}
              as={:advanced_settings}
              phx-change="update_advanced_settings"
              class="grid grid-cols-1 md:grid-cols-2 gap-6"
            >
              <!-- Max Tokens -->
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <label class="label">
                    <span class="label-text">Max Tokens</span>
                  </label>
                  <div class="flex items-center gap-2">
                    <span class={[
                      "badge",
                      if(Map.get(assigns, :max_tokens_active, false),
                        do: "badge-success",
                        else: "badge-ghost"
                      )
                    ]}>
                      {if Map.get(assigns, :max_tokens_active, false), do: "Active", else: "Inactive"}
                    </span>
                    <input
                      type="checkbox"
                      id="max_tokens_active_switch"
                      name="max_tokens_active"
                      class="toggle toggle-sm"
                      checked={Map.get(assigns, :max_tokens_active, false)}
                    />
                  </div>
                </div>
                <div class="space-y-2">
                  <input
                    type="range"
                    id="max_tokens_slider"
                    name="max_tokens"
                    value={Map.get(assigns, :max_tokens, 4000)}
                    min="1"
                    max="4096"
                    step="1"
                    class={[
                      "range range-sm",
                      if(!Map.get(assigns, :max_tokens_active, false), do: "opacity-50 pointer-events-none", else: "")
                    ]}
                  />
                  <div class="flex justify-between text-xs text-base-content/70">
                    <span>1</span>
                    <span class="font-medium">{Map.get(assigns, :max_tokens, 4000)}</span>
                    <span>4096</span>
                  </div>
                </div>
                <p class="text-xs text-base-content/70">
                  Maximum number of tokens to generate in the response.
                </p>
              </div>

              <!-- Temperature -->
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <label class="label">
                    <span class="label-text">Temperature</span>
                  </label>
                  <div class="flex items-center gap-2">
                    <span class={[
                      "badge",
                      if(Map.get(assigns, :temperature_active, false),
                        do: "badge-success",
                        else: "badge-ghost"
                      )
                    ]}>
                      {if Map.get(assigns, :temperature_active, false), do: "Active", else: "Inactive"}
                    </span>
                    <input
                      type="checkbox"
                      id="temperature_active_switch"
                      name="temperature_active"
                      class="toggle toggle-sm"
                      checked={Map.get(assigns, :temperature_active, false)}
                    />
                  </div>
                </div>
                <div class="space-y-2">
                  <input
                    type="range"
                    id="temperature_slider"
                    name="temperature"
                    value={round(Map.get(assigns, :temperature, 0.7) * 100)}
                    min="0"
                    max="100"
                    step="1"
                    class={[
                      "range range-sm",
                      if(!Map.get(assigns, :temperature_active, false), do: "opacity-50 pointer-events-none", else: "")
                    ]}
                  />
                  <div class="flex justify-between text-xs text-base-content/70">
                    <span>0.00</span>
                    <span class="font-medium">{Float.round(Map.get(assigns, :temperature, 0.7), 2)}</span>
                    <span>1.00</span>
                  </div>
                </div>
                <p class="text-xs text-base-content/70">
                  Controls randomness. Lower values make responses more focused and deterministic.
                </p>
              </div>

              <!-- Top K -->
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <label class="label">
                    <span class="label-text">Top K</span>
                  </label>
                  <div class="flex items-center gap-2">
                    <span class={[
                      "badge",
                      if(Map.get(assigns, :top_k_active, false),
                        do: "badge-success",
                        else: "badge-ghost"
                      )
                    ]}>
                      {if Map.get(assigns, :top_k_active, false), do: "Active", else: "Inactive"}
                    </span>
                    <input
                      type="checkbox"
                      id="top_k_active_switch"
                      name="top_k_active"
                      class="toggle toggle-sm"
                      checked={Map.get(assigns, :top_k_active, false)}
                    />
                  </div>
                </div>
                <div class="space-y-2">
                  <input
                    type="range"
                    id="top_k_slider"
                    name="top_k"
                    value={Map.get(assigns, :top_k, 5)}
                    min="1"
                    max="5"
                    step="1"
                    class={["range range-sm", if(!Map.get(assigns, :top_k_active, false), do: "opacity-50 pointer-events-none", else: "")]}
                  />
                  <div class="flex justify-between text-xs text-base-content/70">
                    <span>1</span>
                    <span class="font-medium">{Map.get(assigns, :top_k, 5)}</span>
                    <span>5</span>
                  </div>
                </div>
                <p class="text-xs text-base-content/70">
                  Limits the number of highest probability tokens to consider.
                </p>
              </div>

              <!-- Top P -->
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <label class="label">
                    <span class="label-text">Top P</span>
                  </label>
                  <div class="flex items-center gap-2">
                    <span class={[
                      "badge",
                      if(Map.get(assigns, :top_p_active, false),
                        do: "badge-success",
                        else: "badge-ghost"
                      )
                    ]}>
                      {if Map.get(assigns, :top_p_active, false), do: "Active", else: "Inactive"}
                    </span>
                    <input
                      type="checkbox"
                      id="top_p_active_switch"
                      name="top_p_active"
                      class="toggle toggle-sm"
                      checked={Map.get(assigns, :top_p_active, false)}
                    />
                  </div>
                </div>
                <div class="space-y-2">
                  <input
                    type="range"
                    id="top_p_slider"
                    name="top_p"
                    value={round(Map.get(assigns, :top_p, 0.9) * 100)}
                    min="1"
                    max="100"
                    step="1"
                    class={["range range-sm", if(!Map.get(assigns, :top_p_active, false), do: "opacity-50 pointer-events-none", else: "")]}
                  />
                  <div class="flex justify-between text-xs text-base-content/70">
                    <span>0.01</span>
                    <span class="font-medium">{Float.round(Map.get(assigns, :top_p, 0.9), 2)}</span>
                    <span>1.00</span>
                  </div>
                </div>
                <p class="text-xs text-base-content/70">
                  Cumulative probability cutoff for token selection.
                </p>
              </div>
            </.form>
          </div>
        <% end %>

        <%= if Map.get(assigns, :max_tokens_active, false) || Map.get(assigns, :temperature_active, false) || Map.get(assigns, :top_k_active, false) || Map.get(assigns, :top_p_active, false) do %>
          <div class="bg-info/10 text-info-content border border-info/20 rounded-lg p-3">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-information-circle" class="h-4 w-4 text-info" />
              <span class="text-sm font-medium text-info-content">Advanced Parameters Active</span>
            </div>
            <div class="grid grid-cols-2 gap-4 text-xs text-info-content/80">
              <%= if Map.get(assigns, :max_tokens_active, false) do %>
                <div>Max Tokens: {Map.get(assigns, :max_tokens, 4000)}</div>
              <% end %>
              <%= if Map.get(assigns, :temperature_active, false) do %>
                <div>Temperature: {Float.round(Map.get(assigns, :temperature, 0.7), 2)}</div>
              <% end %>
              <%= if Map.get(assigns, :top_k_active, false) do %>
                <div>Top K: {Map.get(assigns, :top_k, 5)}</div>
              <% end %>
              <%= if Map.get(assigns, :top_p_active, false) do %>
                <div>Top P: {Float.round(Map.get(assigns, :top_p, 0.9), 2)}</div>
              <% end %>
            </div>
          </div>
        <% end %>

        <div class="mt-6 flex flex-col space-y-3">
          <button phx-click="execute_eval" class="btn btn-primary w-full">Run Evaluation</button>
          <button type="button" class="btn btn-outline w-full" phx-click="close_drawer">
            Cancel
          </button>
        </div>
      </div>
    <% else %>
      <div class="space-y-4">
        <p class="text-sm text-base-content/70">Loading evaluation...</p>
        <div class="mt-6 flex flex-col space-y-3">
          <button type="button" class="btn btn-outline w-full" phx-click="close_drawer">
            Cancel
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  # Component for advanced AI settings
  defp advanced_settings_content(assigns) do
    ~H"""
    <div class="space-y-6">
      <.form
        for={%{}}
        as={:advanced_settings}
        phx-change="update_advanced_settings"
        class="grid grid-cols-2 gap-6"
      >
        <!-- Max Tokens -->
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <label class="label">
              <span class="label-text">Max Tokens</span>
            </label>
            <div class="flex items-center gap-2">
              <span class={[
                "badge",
                if(Map.get(assigns, :max_tokens_active, false),
                  do: "badge-success",
                  else: "badge-ghost"
                )
              ]}>
                {if Map.get(assigns, :max_tokens_active, false), do: "Active", else: "Inactive"}
              </span>
              <input
                type="checkbox"
                id="max_tokens_active_switch"
                name="max_tokens_active"
                class="toggle toggle-sm"
                checked={Map.get(assigns, :max_tokens_active, false)}
              />
            </div>
          </div>
          <div class="space-y-2">
            <input
              type="range"
              id="max_tokens_slider"
              name="max_tokens"
              value={Map.get(assigns, :max_tokens, 4000)}
              min="1"
              max="4096"
              step="1"
              class={[
                "range range-sm",
                if(!Map.get(assigns, :max_tokens_active, false), do: "opacity-50 pointer-events-none", else: "")
              ]}
            />
            <div class="flex justify-between text-xs text-base-content/70">
              <span>1</span>
              <span class="font-medium">{Map.get(assigns, :max_tokens, 4000)}</span>
              <span>4096</span>
            </div>
          </div>
          <p class="text-xs text-base-content/70">
            Maximum number of tokens to generate in the response.
          </p>
        </div>

        <!-- Temperature -->
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <label class="label">
              <span class="label-text">Temperature</span>
            </label>
            <div class="flex items-center gap-2">
              <span class={[
                "badge",
                if(Map.get(assigns, :temperature_active, false),
                  do: "badge-success",
                  else: "badge-ghost"
                )
              ]}>
                {if Map.get(assigns, :temperature_active, false), do: "Active", else: "Inactive"}
              </span>
              <input
                type="checkbox"
                id="temperature_active_switch"
                name="temperature_active"
                class="toggle toggle-sm"
                checked={Map.get(assigns, :temperature_active, false)}
              />
            </div>
          </div>
          <div class="space-y-2">
            <input
              type="range"
              id="temperature_slider"
              name="temperature"
              value={round(Map.get(assigns, :temperature, 0.7) * 100)}
              min="0"
              max="100"
              step="1"
              class={[
                "range range-sm",
                if(!Map.get(assigns, :temperature_active, false), do: "opacity-50 pointer-events-none", else: "")
              ]}
            />
            <div class="flex justify-between text-xs text-base-content/70">
              <span>0.00</span>
              <span class="font-medium">{Float.round(Map.get(assigns, :temperature, 0.7), 2)}</span>
              <span>1.00</span>
            </div>
          </div>
          <p class="text-xs text-base-content/70">
            Controls randomness. Lower values make responses more focused and deterministic.
          </p>
        </div>

        <!-- Top K -->
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <label class="label">
              <span class="label-text">Top K</span>
            </label>
            <div class="flex items-center gap-2">
              <span class={[
                "badge",
                if(Map.get(assigns, :top_k_active, false),
                  do: "badge-success",
                  else: "badge-ghost"
                )
              ]}>
                {if Map.get(assigns, :top_k_active, false), do: "Active", else: "Inactive"}
              </span>
              <input
                type="checkbox"
                id="top_k_active_switch"
                name="top_k_active"
                class="toggle toggle-sm"
                checked={Map.get(assigns, :top_k_active, false)}
              />
            </div>
          </div>
          <div class="space-y-2">
            <input
              type="range"
              id="top_k_slider"
              name="top_k"
              value={Map.get(assigns, :top_k, 5)}
              min="1"
              max="5"
              step="1"
              class={["range range-sm", if(!Map.get(assigns, :top_k_active, false), do: "opacity-50 pointer-events-none", else: "")]}
            />
            <div class="flex justify-between text-xs text-base-content/70">
              <span>1</span>
              <span class="font-medium">{Map.get(assigns, :top_k, 5)}</span>
              <span>5</span>
            </div>
          </div>
          <p class="text-xs text-base-content/70">
            Limits the number of highest probability tokens to consider.
          </p>
        </div>

        <!-- Top P -->
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <label class="label">
              <span class="label-text">Top P</span>
            </label>
            <div class="flex items-center gap-2">
              <span class={[
                "badge",
                if(Map.get(assigns, :top_p_active, false),
                  do: "badge-success",
                  else: "badge-ghost"
                )
              ]}>
                {if Map.get(assigns, :top_p_active, false), do: "Active", else: "Inactive"}
              </span>
              <input
                type="checkbox"
                id="top_p_active_switch"
                name="top_p_active"
                class="toggle toggle-sm"
                checked={Map.get(assigns, :top_p_active, false)}
              />
            </div>
          </div>
          <div class="space-y-2">
            <input
              type="range"
              id="top_p_slider"
              name="top_p"
              value={round(Map.get(assigns, :top_p, 0.9) * 100)}
              min="1"
              max="100"
              step="1"
              class={["range range-sm", if(!Map.get(assigns, :top_p_active, false), do: "opacity-50 pointer-events-none", else: "")]}
            />
            <div class="flex justify-between text-xs text-base-content/70">
              <span>0.01</span>
              <span class="font-medium">{Float.round(Map.get(assigns, :top_p, 0.9), 2)}</span>
              <span>1.00</span>
            </div>
          </div>
          <p class="text-xs text-base-content/70">
            Cumulative probability cutoff for token selection.
          </p>
        </div>
      </.form>

      <div class="col-span-2 flex justify-end pt-4 border-t border-base-300">
        <button phx-click="close_advanced_settings" class="btn btn-outline w-full">
          Close
        </button>
      </div>
    </div>
    """
  end

  defp get_drawer_title("create_eval"), do: "Create New Evaluation"
  defp get_drawer_title("edit_eval"), do: "Edit Evaluation"
  defp get_drawer_title("run_eval"), do: "Run Evaluation"
  defp get_drawer_title(_), do: ""

  defp get_drawer_description("create_eval"), do: "Create a new AI evaluation for your collection"
  defp get_drawer_description("edit_eval"), do: "Edit the selected AI evaluation"
  defp get_drawer_description("run_eval"), do: "Run evaluation against selected model"
  defp get_drawer_description(_), do: ""
end
