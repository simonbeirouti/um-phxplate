defmodule Admin.AiEvalResultsLive do
  @moduledoc """
  LiveView for viewing AI evaluation results.

  This view provides functionality for super admins to view and analyze
  the results of AI evaluations that have been run.
  """
  use Admin, :live_view
  alias Core.AI
  alias Core.AI.EvaluationQueue
  alias Admin.PageMeta
  import Admin.Components.Markdown
  import Admin.Components.{PromptSelector, EvalSelector, EvaluationQueue}

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to eval run updates and queue updates for real-time status changes
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Core.PubSub, "eval_runs")
      Phoenix.PubSub.subscribe(Core.PubSub, "evaluation_queue")

      # Schedule periodic queue status updates
      :timer.send_interval(2000, self(), :update_queue_status)
    end

    {:ok,
     socket
     |> assign(:show_drawer, false)
     |> assign(:selected_eval_run, nil)
     |> assign(:delete_confirmation_id, nil)
     |> assign(:status_filter, "All Status")
     |> assign(:success_filter, "All Results")
     |> assign(:eval_filter, "All Evaluations")
     |> assign(:prompt_filter, "All Prompts")
     |> assign(:page, 1)
     |> assign(:per_page, 10)
     |> assign(:eval_runs, [])
     |> assign(:total_pages, 1)
     |> assign(:total_count, 0)
     |> assign(:screen_mode, "dialog")
     |> assign(:available_evals, load_available_evals())
     |> assign(:available_prompts, load_available_prompts())
     |> assign(:filter_reset_key, 0)
     |> assign(:queue_status, get_queue_status())
     |> load_eval_runs()
     |> PageMeta.assign_metadata(
       title: "AI Eval Results",
       description: "View AI evaluation results",
       url: "/dashboard/ai-eval-results"
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_eval_runs()}
  end

  @impl true
  def handle_event("view_results", %{"id" => id}, socket) do
    eval_run = AI.get_eval_run(id)

    {:noreply,
     socket
     |> assign(:show_drawer, true)
     |> assign(:selected_eval_run, eval_run)}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_drawer, false)
     |> assign(:selected_eval_run, nil)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 1)
     |> load_eval_runs()}
  end

  @impl true
  def handle_event("filter_success", %{"success" => success}, socket) do
    {:noreply,
     socket
     |> assign(:success_filter, success)
     |> assign(:page, 1)
     |> load_eval_runs()}
  end

  @impl true
  def handle_event("filter_eval", %{"eval" => eval_value}, socket) do
    {:noreply,
     socket
     |> assign(:eval_filter, eval_value)
     |> assign(:page, 1)
     |> load_eval_runs()}
  end

  @impl true
  def handle_event("filter_prompt", %{"prompt_name" => prompt_value}, socket) do
    {:noreply,
     socket
     |> assign(:prompt_filter, prompt_value)
     |> assign(:page, 1)
     |> load_eval_runs()}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_eval_runs()
     |> push_patch(to: ~p"/dashboard/ai-results?page=#{page}")}
  end

  @impl true
  def handle_event("set_screen_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :screen_mode, mode)}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, "All Status")
     |> assign(:success_filter, "All Results")
     |> assign(:eval_filter, "All Evaluations")
     |> assign(:prompt_filter, "All Prompts")
     |> assign(:page, 1)
     |> assign(:filter_reset_key, socket.assigns.filter_reset_key + 1)
     |> load_eval_runs()}
  end

  @impl true
  def handle_event("delete_eval_run", %{"id" => id}, socket) do
    socket =
      if Map.has_key?(socket.assigns, :delete_confirmation_id) do
        socket
      else
        assign(socket, :delete_confirmation_id, nil)
      end

    {:noreply, assign(socket, :delete_confirmation_id, String.to_integer(id))}
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    socket =
      if Map.has_key?(socket.assigns, :delete_confirmation_id) do
        socket
      else
        assign(socket, :delete_confirmation_id, nil)
      end

    eval_run_id = String.to_integer(id)

    case AI.delete_eval_run(eval_run_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:delete_confirmation_id, nil)
         |> load_eval_runs()
         |> put_flash(:info, "Evaluation run deleted successfully")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:delete_confirmation_id, nil)
         |> put_flash(:error, "Failed to delete evaluation run")}
    end
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    socket =
      if Map.has_key?(socket.assigns, :delete_confirmation_id) do
        socket
      else
        assign(socket, :delete_confirmation_id, nil)
      end

    {:noreply, assign(socket, :delete_confirmation_id, nil)}
  end

  @impl true
  def handle_info({:eval_run_updated, updated_eval_run}, socket) do
    # Update the eval run in the current list if it exists
    updated_eval_runs =
      Enum.map(socket.assigns.eval_runs, fn eval_run ->
        if eval_run.id == updated_eval_run.id do
          # Preload associations to match the expected structure
          AI.get_eval_run(updated_eval_run.id) || updated_eval_run
        else
          eval_run
        end
      end)

    # Also update the selected eval run if it's the one being viewed
    updated_selected_eval_run =
      if socket.assigns.selected_eval_run &&
           socket.assigns.selected_eval_run.id == updated_eval_run.id do
        AI.get_eval_run(updated_eval_run.id) || updated_eval_run
      else
        socket.assigns.selected_eval_run
      end

    {:noreply,
     socket
     |> assign(:eval_runs, updated_eval_runs)
     |> assign(:selected_eval_run, updated_selected_eval_run)}
  end

  @impl true
  def handle_info(:update_queue_status, socket) do
    {:noreply, assign(socket, :queue_status, get_queue_status())}
  end

  @impl true
  def handle_info({:queue_updated, _queue_data}, socket) do
    {:noreply, assign(socket, :queue_status, get_queue_status())}
  end

  defp load_eval_runs(socket) do
    # Convert display text back to database values for status filter
    status_value =
      case socket.assigns.status_filter do
        "All Status" -> "all"
        other -> other
      end

    opts = [
      status: status_value
    ]

    # Filter by eval name
    opts =
      if socket.assigns.eval_filter not in ["All Evaluations", "No Eval Selected"] do
        case Enum.find(socket.assigns.available_evals, &(&1.name == socket.assigns.eval_filter)) do
          nil -> opts
          eval -> Keyword.put(opts, :eval_id, eval.id)
        end
      else
        opts
      end

    # Filter by prompt name
    opts =
      if socket.assigns.prompt_filter not in ["All Prompts"] do
        case socket.assigns.prompt_filter do
          "Default System" ->
            # Filter for evaluation runs with prompt_id: nil
            Keyword.put(opts, :prompt_id, nil)

          prompt_name ->
            case Enum.find(
                   socket.assigns.available_prompts,
                   &(&1.name == prompt_name)
                 ) do
              nil -> opts
              prompt -> Keyword.put(opts, :prompt_id, prompt.id)
            end
        end
      else
        opts
      end

    result = AI.list_all_eval_runs(socket.assigns.page, socket.assigns.per_page, opts)

    # Apply success filtering (client-side since it depends on results analysis)
    # Convert display text back to database values for success filter
    success_value =
      case socket.assigns.success_filter do
        "All Results" -> "all"
        other -> other
      end

    filtered_eval_runs =
      case success_value do
        "all" ->
          result.eval_runs

        success_filter ->
          Enum.filter(result.eval_runs, fn eval_run ->
            get_eval_run_success_status(eval_run) == success_filter
          end)
      end

    socket
    |> assign(:eval_runs, filtered_eval_runs)
    |> assign(:total_pages, result.total_pages)
    |> assign(:total_count, result.total_count)
  rescue
    # Handle case where tables don't exist yet
    _ ->
      socket
      |> assign(:eval_runs, [])
      |> assign(:total_pages, 1)
      |> assign(:total_count, 0)
  end

  defp load_available_evals do
    try do
      AI.list_evals()
    rescue
      _ -> []
    end
  end

  defp load_available_prompts do
    try do
      database_prompts = AI.list_prompts_for_chat()

      # Add the virtual "Default System" prompt that represents prompt_id: nil
      default_system_prompt = %{
        id: nil,
        name: "Default System",
        description: "Built-in default system prompt",
        category: "system"
      }

      [default_system_prompt | database_prompts]
    rescue
      _ ->
        [
          %{
            id: nil,
            name: "Default System",
            description: "Built-in default system prompt",
            category: "system"
          }
        ]
    end
  end

  defp format_score(score) when is_float(score) do
    # Handle both old format (0.0-1.0) and new format (1.0-5.0)
    if score <= 1.0 do
      # Old format: show as percentage
      "#{:erlang.float_to_binary(score * 100, decimals: 1)}%"
    else
      # New format: show as score out of 5
      "#{:erlang.float_to_binary(score, decimals: 1)}/5.0"
    end
  end

  defp format_score(score) when is_integer(score) do
    if score <= 1 do
      "#{score * 100}%"
    else
      "#{score}/5"
    end
  end

  defp format_score(_), do: "N/A"

  defp format_duration(started_at, completed_at)
       when not is_nil(started_at) and not is_nil(completed_at) do
    diff = DateTime.diff(completed_at, started_at, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m #{rem(diff, 60)}s"
      true -> "#{div(diff, 3600)}h #{div(rem(diff, 3600), 60)}m"
    end
  end

  defp format_duration(_, _), do: "N/A"

  defp status_badge_class(status) do
    case status do
      "completed" -> "bg-green-100 text-green-800"
      "failed" -> "bg-red-100 text-red-800"
      "running" -> "bg-blue-100 text-blue-800"
      "pending" -> "bg-yellow-100 text-yellow-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp get_test_case_results(results) when is_map(results) do
    # Handle new format: results with test case details (input, output, expected, etc.)
    new_format_results =
      results
      |> Enum.filter(fn {_key, value} ->
        is_map(value) and
          ((Map.has_key?(value, :input) and Map.has_key?(value, :output)) or
             (Map.has_key?(value, "input") and Map.has_key?(value, "output")))
      end)
      |> Enum.sort_by(fn {key, _value} -> key end)

    # If we have new format results, use them
    if not Enum.empty?(new_format_results) do
      # Normalize the results to use atom keys for consistency
      new_format_results
      |> Enum.map(fn {test_name, result} ->
        normalized_result = %{
          input: Map.get(result, :input) || Map.get(result, "input"),
          output: Map.get(result, :output) || Map.get(result, "output"),
          expected: Map.get(result, :expected) || Map.get(result, "expected"),
          score: Map.get(result, :score) || Map.get(result, "score"),
          passed: Map.get(result, :passed) || Map.get(result, "passed"),
          reasoning: Map.get(result, :reasoning) || Map.get(result, "reasoning"),
          error: Map.get(result, :error) || Map.get(result, "error")
        }

        {test_name, normalized_result}
      end)
    else
      # Handle old format: convert detailed_scores to displayable format
      case Map.get(results, "detailed_scores") do
        detailed_scores when is_map(detailed_scores) ->
          detailed_scores
          |> Enum.map(fn {test_name, score} ->
            {test_name,
             %{
               input: "Test case: #{test_name}",
               output: "Score: #{score}",
               expected: "Performance evaluation",
               score: score,
               passed: score >= 0.8,
               reasoning: "Legacy format - detailed evaluation not available"
             }}
          end)
          |> Enum.sort_by(fn {key, _value} -> key end)

        _ ->
          # If no recognizable format, create a generic entry
          [
            {
              "evaluation_summary",
              %{
                input: "Evaluation completed",
                output: inspect(results),
                expected: "Evaluation results",
                score: nil,
                passed: false,
                reasoning: "Legacy format - unable to parse detailed results"
              }
            }
          ]
      end
    end
  end

  defp get_test_case_results(_), do: []

  defp get_eval_run_success_status(eval_run) do
    case eval_run.status do
      "completed" ->
        if eval_run.results && is_map(eval_run.results) do
          test_results = get_test_case_results(eval_run.results)

          if Enum.empty?(test_results) do
            "unknown"
          else
            # Check if all test cases passed
            all_passed =
              Enum.all?(test_results, fn {_name, result} ->
                Map.get(result, :passed, false)
              end)

            if all_passed, do: "success", else: "partial"
          end
        else
          "unknown"
        end

      "failed" ->
        "failed"

      _ ->
        "unknown"
    end
  end

  defp success_status_badge_class(success_status) do
    case success_status do
      "success" -> "bg-green-100 text-green-800"
      "partial" -> "bg-yellow-100 text-yellow-800"
      "failed" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp success_status_text(success_status) do
    case success_status do
      "success" -> "All Passed"
      "partial" -> "Some Failed"
      "failed" -> "Failed"
      _ -> "Unknown"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]" phx-hook="TimezoneDetector" id="timezone-detector">
      <.header>
        AI Eval Results
        <:subtitle>View and analyze AI evaluation results</:subtitle>
      </.header>

      <.evaluation_queue_accordion queue_status={@queue_status} />

      <div class="mt-4">
        <div class="mb-3 flex items-center justify-between md:justify-start">
          <span class="text-sm font-medium text-gray-700">Filters</span>
          <div class="md:hidden">
            <button class="btn btn-outline btn-lg w-auto" phx-click="reset_filters">
              <.icon name="hero-arrow-path" class="w-4 h-4 -mx-4" />
            </button>
          </div>
        </div>
        <div
          class="grid grid-cols-2 gap-3 md:flex md:flex-wrap md:gap-4 md:items-center"
          id={"filters-#{@filter_reset_key}"}
        >
          <form phx-change="filter_status" class="w-full md:w-auto">
            <select
              id="status-filter"
              name="status"
              class="select select-bordered w-full md:w-48"
              phx-change="filter_status"
            >
              <option selected={@status_filter == "All Status"}>All Status</option>
              <option value="completed" selected={@status_filter == "completed"}>Completed</option>
              <option value="failed" selected={@status_filter == "failed"}>Failed</option>
              <option value="running" selected={@status_filter == "running"}>Running</option>
            </select>
          </form>

          <form phx-change="filter_success" class="w-full md:w-auto">
            <select
              id="success-filter"
              name="success"
              class="select select-bordered w-full md:w-48"
              phx-change="filter_success"
            >
              <option selected={@success_filter == "All Results"}>All Results</option>
              <option value="success" selected={@success_filter == "success"}>All Passed</option>
              <option value="partial" selected={@success_filter == "partial"}>Some Failed</option>
              <option value="failed" selected={@success_filter == "failed"}>Failed</option>
            </select>
          </form>

          <%= if not Enum.empty?(@available_evals) do %>
            <div class="w-full md:w-auto">
              <.eval_selector
                available_evals={@available_evals}
                selected_eval={@eval_filter}
                on_change="filter_eval"
                class="w-full md:w-48"
                id="eval-filter"
                show_default={false}
                show_all_option={true}
                all_option_text="All Evaluations"
                all_option_value="All Evaluations"
                key={"eval-#{@filter_reset_key}"}
              />
            </div>
          <% end %>

          <%= if not Enum.empty?(@available_prompts) do %>
            <div class="w-full md:w-auto">
              <.prompt_selector
                available_prompts={@available_prompts}
                selected_prompt={@prompt_filter}
                on_change="filter_prompt"
                class="w-full md:w-48"
                id="prompt-filter"
                show_default={false}
                show_all_option={true}
                all_option_text="All Prompts"
                all_option_value="All Prompts"
                key={"prompt-#{@filter_reset_key}"}
              />
            </div>
          <% end %>

          <div class="hidden md:flex w-full md:w-auto justify-center md:justify-start">
            <button class="btn btn-outline btn-lg w-full md:w-auto" phx-click="reset_filters">
              <.icon name="hero-arrow-path" class="w-4 h-4 -mx-4" />
            </button>
          </div>
        </div>
      </div>

      <div class="mt-6">
        <%= if Enum.empty?(@eval_runs) do %>
          <.empty_state />
        <% else %>
          <.results_grid eval_runs={@eval_runs} delete_confirmation_id={@delete_confirmation_id} />
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

      <dialog id="ai-results-modal" class={["modal", if(@show_drawer && @selected_eval_run, do: "modal-open")]}>
        <div class="modal-box max-w-6xl max-h-[90vh] overflow-y-auto">
          <h3 class="font-bold text-lg">Evaluation Results</h3>
          <p class="py-4">Detailed results for this evaluation run</p>
          <.eval_run_details eval_run={@selected_eval_run} />
        </div>
        <form method="dialog" class="modal-backdrop" phx-click="close_drawer">
          <button>close</button>
        </form>
      </dialog>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <div class="mx-auto h-12 w-12 text-base-content/40">
        <.icon name="hero-chart-bar" class="h-12 w-12" />
      </div>
      <h3 class="mt-2 text-sm font-medium text-base-content">No evaluation results found</h3>
      <p class="mt-1 text-sm text-base-content/70">
        Run some evaluations to see results here.
      </p>
    </div>
    """
  end

  defp results_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-6">
      <%= for eval_run <- @eval_runs do %>
        <%= if eval_run.eval do %>
        <div class="bg-base-100 rounded-lg border border-base-300 shadow-sm hover:shadow-md transition-shadow duration-200">
          <div class="p-6">
            <div class="flex items-start justify-between mb-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <h3 class="text-lg font-semibold text-base-content truncate">
                    {eval_run.eval.name}
                  </h3>
                  <%= if not Enum.empty?(get_active_advanced_params(eval_run)) do %>
                    <.icon name="hero-cog" class="h-4 w-4 text-info flex-shrink-0" title="Advanced parameters used" />
                  <% end %>
                </div>
                <%= if eval_run.prompt do %>
                  <p class="text-sm text-base-content/70 mt-1">
                    Prompt: {String.slice(eval_run.prompt.name, 0, 25)}{if String.length(eval_run.prompt.name) > 25, do: "..."}
                  </p>
                <% end %>
              </div>
              <div class="flex flex-col gap-1 ml-2">
                <span class={[
                  "inline-flex px-2 py-1 text-xs font-semibold rounded-full whitespace-nowrap items-center",
                  status_badge_class(eval_run.status)
                ]}>
                  <%= if eval_run.status == "running" do %>
                    <svg
                      class="animate-spin -ml-1 mr-1 h-3 w-3 text-blue-800"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        class="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        stroke-width="4"
                      >
                      </circle>
                      <path
                        class="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                      >
                      </path>
                    </svg>
                  <% end %>
                  {String.capitalize(eval_run.status)}
                </span>
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4 mb-4">
              <div>
                <p class="text-sm font-medium text-base-content/70">Model</p>
                <p class="text-sm text-base-content mt-1">{get_display_model_name(eval_run.model)}</p>
              </div>
              <div>
                <div class="flex items-center gap-2">
                  <p class="text-sm font-medium text-base-content/70">Score</p>
                  <% success_status = get_eval_run_success_status(eval_run) %>
                    <%= if success_status != "unknown" do %>
                      <span class={[
                        "inline-flex px-2 py-1 text-xs font-semibold rounded-full whitespace-nowrap",
                        success_status_badge_class(success_status)
                      ]}>
                        {success_status_text(success_status)}
                      </span>
                    <% end %>
                </div>
                <p class="text-sm text-base-content mt-1">
                  <%= if eval_run.score do %>
                    <span class="font-semibold">{format_score(eval_run.score)}</span>
                  <% else %>
                    N/A
                  <% end %>
                </p>
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4 mb-4">
              <div>
                <p class="text-sm font-medium text-base-content/70">Duration</p>
                <p class="text-sm text-base-content/80 mt-1">
                  {format_duration(eval_run.started_at, eval_run.completed_at)}
                </p>
              </div>
              <div>
                <p class="text-sm font-medium text-base-content/70">Run Date</p>
                <p class="text-sm text-base-content/80 mt-1" data-utc-time={DateTime.to_iso8601(eval_run.inserted_at)}>
                  {Calendar.strftime(eval_run.inserted_at, "%d/%m, %H:%M")}
                </p>
              </div>
            </div>

            <div class="flex justify-end">
              <%= if @delete_confirmation_id == eval_run.id do %>
                <div class="flex gap-2 w-full">
                  <button
                    class="btn btn-outline btn-success btn-sm flex-1"
                    phx-click="confirm_delete"
                    phx-value-id={eval_run.id}
                  >
                    <.icon name="hero-check" class="h-4 w-4 mr-2" /> Confirm
                  </button>
                  <button
                    class="btn btn-outline btn-error btn-sm flex-1"
                    phx-click="cancel_delete"
                  >
                    <.icon name="hero-x-mark" class="h-4 w-4 mr-2" /> Cancel
                  </button>
                </div>
              <% else %>
                <div class="flex gap-2 w-full">
                  <button
                    class="btn btn-outline btn-sm flex-1"
                    phx-click="view_results"
                    phx-value-id={eval_run.id}
                    disabled={eval_run.status not in ["completed", "failed"]}
                  >
                    <.icon name="hero-eye" class="h-4 w-4 mr-2" /> View Results
                  </button>
                  <button
                    class="btn btn-outline btn-error btn-sm px-3"
                    phx-click="delete_eval_run"
                    phx-value-id={eval_run.id}
                  >
                    <.icon name="hero-trash" class="h-4 w-4" />
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        <% else %>
          <div class="bg-base-100 rounded-lg border border-base-300 shadow-sm p-6">
            <p class="text-error">Error: Evaluation data missing for this run.</p>
            <p class="text-xs text-base-content/70">Run ID: {eval_run.id}</p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp eval_run_details(assigns) do
    ~H"""
    <%= if @eval_run do %>
      <div class="space-y-6">

        <div class="bg-base-200 rounded-lg p-4">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
            <div>
              <h3 class="text-lg font-medium text-base-content">{@eval_run.eval.name}</h3>
              <p class="text-sm text-base-content/70 mt-1">Model: {get_display_model_name(@eval_run.model)}</p>
              <%= if @eval_run.prompt do %>
                <p class="text-sm text-base-content/70">Prompt: {@eval_run.prompt.name}</p>
              <% end %>
              <% active_params = get_active_advanced_params(@eval_run) %>
              <%= if not Enum.empty?(active_params) do %>
                <div class="mt-3">
                  <div class="flex items-center gap-2 mb-2">
                    <.icon name="hero-cog" class="h-4 w-4 text-info" />
                    <span class="text-sm font-medium text-info-content">Parameters: </span>
                    <%= for param <- active_params do %>
                      <span class="inline-flex items-center px-2 py-1 text-xs font-medium bg-info/20 text-info-content rounded-full">
                        {param}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
              <div class="text-right">
                <span class={[
                  "inline-flex px-3 py-1 text-sm font-semibold rounded-full",
                  status_badge_class(@eval_run.status)
                ]}>
                  {String.capitalize(@eval_run.status)}
                </span>
                <%= if @eval_run.score do %>
                  <p class="text-2xl font-bold text-base-content mt-2">
                    {format_score(@eval_run.score)}
                  </p>
                  <p class="text-sm text-base-content/70">Overall Score</p>
                <% end %>
              </div>
            </div>

            <%= if @eval_run.status == "completed" and @eval_run.results do %>
              <% test_results = get_test_case_results(@eval_run.results) %>
              <% {passed_count, total_count, avg_score, length_analysis} =
                calculate_summary_stats(test_results) %>

              <div class="border-t border-base-300 pt-4">
                <h4 class="text-lg font-medium text-base-content mb-3">Evaluation Summary</h4>
                <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div class="text-center">
                    <div class="text-2xl font-bold text-base-content">{passed_count}/{total_count}</div>
                    <div class="text-sm text-base-content/70">Tests Passed</div>
                  </div>
                  <div class="text-center">
                    <div class="text-2xl font-bold text-base-content">
                      {Float.round(passed_count / total_count * 100, 1)}%
                    </div>
                    <div class="text-sm text-base-content/70">Pass Rate</div>
                  </div>
                  <div class="text-center">
                    <div class="text-2xl font-bold text-base-content">{format_score(avg_score)}</div>
                    <div class="text-sm text-base-content/70">Avg Score</div>
                  </div>
                  <div class="text-center">
                    <div class="text-2xl font-bold text-base-content">{length_analysis.avg_ratio}x</div>
                    <div class="text-sm text-base-content/70">Avg Length Ratio</div>
                  </div>
                </div>
                <%= if length_analysis.avg_ratio > 3.0 do %>
                  <div class="mt-3 p-3 bg-warning/20 border border-warning/30 rounded text-sm text-warning-content">
                    ⚠️ Responses are significantly longer than expected. Consider reviewing conciseness instructions.
                  </div>
              <% end %>
            </div>

          <% end %>
        </div>

        <%= if @eval_run.status == "completed" and @eval_run.results do %>
          <div>
            <h4 class="text-lg font-medium text-base-content mb-4">Test Case Results</h4>
            <div class="space-y-4">
              <%= for {test_name, result} <- get_test_case_results(@eval_run.results) do %>
                <div class="border border-base-300 rounded-lg p-4">
                  <div class="flex items-center justify-between mb-3">
                    <h5 class="text-md font-medium text-base-content">{test_name}</h5>
                    <div class="flex items-center gap-2">
                      <%= if Map.get(result, :score) do %>
                        <span class="text-sm font-medium text-base-content/80">
                          Score: {format_score(Map.get(result, :score))}
                        </span>
                      <% end %>
                      <span class={[
                        "inline-flex px-2 py-1 text-xs font-semibold rounded-full",
                        if(Map.get(result, :passed),
                          do: "bg-success/20 text-success-content",
                          else: "bg-error/20 text-error-content"
                        )
                      ]}>
                        {if Map.get(result, :passed), do: "Passed", else: "Failed"}
                      </span>
                    </div>
                  </div>

                  <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <div>
                      <h6 class="text-sm font-medium text-base-content/80 mb-2">Input</h6>
                      <div class="bg-base-200 rounded p-3 text-sm">
                        <pre class="whitespace-pre-wrap">{Map.get(result, :input, "")}</pre>
                      </div>
                    </div>

                    <div>
                      <h6 class="text-sm font-medium text-base-content/80 mb-2">Expected Output</h6>
                      <div class="bg-base-200 rounded p-3 text-sm">
                        <pre class="whitespace-pre-wrap">{Map.get(result, :expected, "")}</pre>
                      </div>
                    </div>

                    <div>
                      <h6 class="text-sm font-medium text-base-content/80 mb-2">
                        Actual Output <% expected_len =
                          String.length(Map.get(result, :expected, "")) %>
                        <% actual_len = String.length(Map.get(result, :output, "")) %>
                        <%= if expected_len > 0 and actual_len > 0 do %>
                          <span class={[
                            "text-xs px-1 py-0.5 rounded ml-2",
                            if(actual_len > expected_len * 3,
                              do: "bg-error/20 text-error-content",
                              else: "bg-success/20 text-success-content"
                            )
                          ]}>
                            {Float.round(actual_len / expected_len, 1)}x length
                          </span>
                        <% end %>
                      </h6>
                      <div class="bg-base-200 rounded p-3 text-sm max-h-40 overflow-y-auto">
                        <div class="prose prose-sm max-w-none">
                          {to_html(Map.get(result, :output, ""))}
                        </div>
                      </div>
                    </div>
                  </div>

                  <%= if Map.get(result, :reasoning) do %>
                    <div class="mt-4">
                      <h6 class="text-sm font-medium text-base-content/80 mb-2">Judge Evaluation</h6>
                      <div class="bg-info/10 rounded p-3 text-sm">
                        <pre class="whitespace-pre-wrap">{Map.get(result, :reasoning)}</pre>
                      </div>
                    </div>
                  <% end %>

                  <%= if Map.get(result, :error) do %>
                    <div class="mt-4">
                      <h6 class="text-sm font-medium text-error mb-2">Error</h6>
                      <div class="bg-error/10 rounded p-3 text-sm text-error-content">
                        <pre class="whitespace-pre-wrap">{Map.get(result, :error)}</pre>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @eval_run.status == "failed" and @eval_run.results do %>
        <div>
          <h4 class="text-lg font-medium text-error mb-4">Error Details</h4>
          <div class="bg-error/10 border border-error/20 rounded-lg p-4">
            <pre class="text-sm text-error-content whitespace-pre-wrap">{inspect(@eval_run.results)}</pre>
          </div>
        </div>
      <% end %>

      <div class="flex justify-end pt-4 border-t border-base-300">
        <button class="btn btn-outline w-full" phx-click="close_drawer">
          Close
        </button>
      </div>
    <% else %>
      <div class="space-y-4">
        <p class="text-sm text-base-content/70">Loading evaluation results...</p>
        <div class="flex justify-end pt-4 border-t border-base-300">
          <button class="btn btn-outline w-full" phx-click="close_drawer">
            Close
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  defp calculate_summary_stats(test_results) do
    passed_count =
      Enum.count(test_results, fn {_name, result} -> Map.get(result, :passed, false) end)

    total_count = length(test_results)

    avg_score =
      Enum.sum(Enum.map(test_results, fn {_name, result} -> Map.get(result, :score, 0.0) end)) /
        total_count

    length_analysis = calculate_length_analysis(test_results)
    {passed_count, total_count, avg_score, length_analysis}
  end

  defp calculate_length_analysis(test_results) do
    ratios =
      test_results
      |> Enum.map(fn {_name, result} ->
        expected_len = String.length(Map.get(result, :expected, ""))
        actual_len = String.length(Map.get(result, :output, ""))

        if expected_len > 0 and actual_len > 0 do
          actual_len / expected_len
        else
          1.0
        end
      end)
      |> Enum.reject(&is_nil/1)

    avg_ratio =
      if Enum.empty?(ratios) do
        1.0
      else
        Enum.sum(ratios) / length(ratios)
      end

    %{
      avg_ratio: Float.round(avg_ratio, 1),
      ratios: ratios
    }
  end

  defp get_queue_status do
    try do
      EvaluationQueue.status()
    rescue
      _ ->
        # Fallback if queue is not available
        %{
          queue_size: 0,
          current_evaluation: nil,
          configuration: %{
            cooldown_ms: 5000,
            max_retries: 3,
            retry_delay_ms: 10000
          },
          statistics: %{
            total_processed: 0,
            successful: 0,
            failed: 0,
            retries: 0,
            started_at: DateTime.utc_now()
          }
        }
    end
  end



  defp get_display_model_name(model) do
    # Convert API ID back to display name, or return as-is if it's already a display name
    case model do
      # If it starts with "claude-", it's an API ID, convert to display name
      "claude-" <> _ -> Core.AI.Models.get_display_name(model)
      # Otherwise, it's already a display name
      display_name -> display_name
    end
  end

  defp get_active_advanced_params(eval_run) do
    params = []

    # Check Max Tokens
    params = if eval_run.max_tokens_active and eval_run.max_tokens do
      ["Max Tokens: #{eval_run.max_tokens}" | params]
    else
      params
    end

    # Check Temperature
    params = if eval_run.temperature_active and eval_run.temperature do
      ["Temperature: #{Float.round(eval_run.temperature, 2)}" | params]
    else
      params
    end

    # Check Top K
    params = if eval_run.top_k_active and eval_run.top_k do
      ["Top K: #{eval_run.top_k}" | params]
    else
      params
    end

    # Check Top P
    params = if eval_run.top_p_active and eval_run.top_p do
      ["Top P: #{Float.round(eval_run.top_p, 2)}" | params]
    else
      params
    end

    # Reverse to maintain the order we added them
    Enum.reverse(params)
  end
end
