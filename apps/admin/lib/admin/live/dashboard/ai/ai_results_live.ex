defmodule Admin.AiResultsLive do
  @moduledoc """
  LiveView for viewing AI usage timeline and statistics.

  This view provides comprehensive tracking of AI model usage including:
  - Model usage statistics and success rates
  - Timeline visualization of AI activity
  - Error tracking and debugging information
  - User usage patterns
  - Performance metrics
  """
  use Admin, :live_view
  alias Core.AI
  alias Admin.PageMeta
  alias Admin.Components.AI.ModelSelector

  @time_range_options [
    {"Last 7 days", 7},
    {"Last 30 days", 30},
    {"Last 90 days", 90},
    {"Last year", 365}
  ]

  @status_options [
    {"All Status", "all"},
    {"Success", "success"},
    {"Error", "error"},
    {"Timeout", "timeout"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to realtime usage updates if connected
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Core.PubSub, "ai_usage")
      Phoenix.PubSub.subscribe(Core.PubSub, "ai_errors")
    end

    {:ok,
     socket
     |> assign(:selected_model, "All Models")
     |> assign(:time_range, "Last 30 days")
     |> assign(:status_filter, "All Status")
     |> assign(:page, 1)
     |> assign(:per_page, 20)
     |> assign(:errors_page, 1)
     |> assign(:errors_per_page, 10)
     |> assign(:show_errors_drawer, false)
     |> assign(:selected_error, nil)
     |> assign(:filter_reset_key, 0)
     |> assign(:time_range_options, @time_range_options)
     |> assign(:status_options, @status_options)
     |> assign(:errors_result, %{errors: [], total_count: 0, total_pages: 1, page: 1, per_page: 10})
     |> assign(:screen_mode, "dialog")
     |> load_usage_data()
     |> PageMeta.assign_metadata(
       title: "AI Results",
       description: "View AI model usage statistics and timeline",
       url: "/dashboard/super_admin/ai-results"
     )}
  end

  @impl true
  def handle_params(params, url, socket) do
    uri = URI.parse(url)
    socket = update(socket, :layout_data, &Map.put(&1, :current_path, uri.path))

    page = String.to_integer(Map.get(params, "page", "1"))
    errors_page = String.to_integer(Map.get(params, "errors_page", "1"))
    model = Map.get(params, "model", "All Models")
    time_range_param = Map.get(params, "time_range", "Last 30 days")
    # Convert numeric time_range params to labels for backward compatibility
    time_range = case time_range_param do
      "7" -> "Last 7 days"
      "30" -> "Last 30 days"
      "90" -> "Last 90 days"
      "365" -> "Last year"
      label when is_binary(label) -> label
    end
    status_param = Map.get(params, "status", "All Status")
    # Convert status values to labels for backward compatibility
    status = case status_param do
      "all" -> "All Status"
      "success" -> "Success"
      "error" -> "Error"
      "timeout" -> "Timeout"
      label when is_binary(label) -> label
    end

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:errors_page, errors_page)
     |> assign(:selected_model, model)
     |> assign(:time_range, time_range)
     |> assign(:status_filter, status)
     |> load_usage_data()}
  end

  @impl true
  def handle_event("select_model", %{"model" => model}, socket) do
    {:noreply,
     socket
     |> assign(:selected_model, model)
     |> assign(:page, 1)
     |> assign(:errors_page, 1)
     |> load_usage_data()
     |> push_patch(to: build_url(socket, %{model: model, page: 1, errors_page: 1}))}
  end

  @impl true
  def handle_event("filter_time_range", %{"time_range" => time_range}, socket) do
    {:noreply,
     socket
     |> assign(:time_range, time_range)
     |> assign(:page, 1)
     |> assign(:errors_page, 1)
     |> load_usage_data()
     |> push_patch(to: build_url(socket, %{time_range: time_range, page: 1, errors_page: 1}))}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 1)
     |> assign(:errors_page, 1)
     |> load_usage_data()
     |> push_patch(to: build_url(socket, %{status: status, page: 1, errors_page: 1}))}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_model, "All Models")
     |> assign(:time_range, "Last 30 days")
     |> assign(:status_filter, "All Status")
     |> assign(:page, 1)
     |> assign(:errors_page, 1)
     |> assign(:filter_reset_key, socket.assigns.filter_reset_key + 1)
     |> load_usage_data()
     |> push_patch(to: ~p"/dashboard/super_admin/ai-results")}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_usage_data()
     |> push_patch(to: build_url(socket, %{page: page}))}
  end

  @impl true
  def handle_event("paginate_errors", %{"page" => page}, socket) do
    page = String.to_integer(page)

    {:noreply,
     socket
     |> assign(:errors_page, page)
     |> load_usage_data()
     |> push_patch(to: build_url(socket, %{errors_page: page}))}
  end

  @impl true
  def handle_event("view_error", %{"error_id" => error_id}, socket) do
    error = Enum.find(socket.assigns.errors_result.errors, &(&1.id == String.to_integer(error_id)))

    {:noreply,
     socket
     |> assign(:show_errors_drawer, true)
     |> assign(:selected_error, error)}
  end

  @impl true
  def handle_event("close_errors_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_errors_drawer, false)
     |> assign(:selected_error, nil)}
  end

  @impl true
  def handle_event("set_screen_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :screen_mode, mode)}
  end

  # Handle realtime updates from PubSub
  @impl true
  def handle_info({:usage_logged, _usage_log}, socket) do
    # Reload all usage data when new usage is logged
    {:noreply, load_usage_data(socket)}
  end

  @impl true
  def handle_info({:error_logged, _usage_log}, socket) do
    # Reload usage data when new errors are logged
    {:noreply, load_usage_data(socket)}
  end

  # Ignore other messages
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        AI Results
        <:subtitle>View AI model usage statistics and timeline</:subtitle>
        <:actions>
          <button class="btn btn-outline btn-lg w-auto" phx-click="reset_filters">
            <.icon name="hero-arrow-path" class="w-4 h-4 md:mr-2" />
            <span class="hidden md:inline">Reset Filters</span>
          </button>
        </:actions>
      </.header>

      <div class="mt-4">
        <label>Filters</label>

        <div
          class="grid grid-cols-3 gap-3 lg:flex lg:flex-wrap lg:gap-4 lg:items-center"
          id={"filters-#{@filter_reset_key}"}
        >
          <!-- Model Filter -->
          <div class="w-full lg:w-auto">
            <ModelSelector.model_selector
              selected_model={@selected_model}
              on_change="select_model"
              class="w-full lg:w-48"
              id={"model-filter-#{@filter_reset_key}"}
              include_all_option={true}
            />
          </div>

          <!-- Time Range Filter -->
          <form phx-change="filter_time_range" class="w-full lg:w-auto">
            <select
              id="time-range-filter"
              name="time_range"
              class="select select-bordered w-full lg:w-48"
              phx-change="filter_time_range"
            >
              <%= for {label, _value} <- @time_range_options do %>
                <option value={label} selected={@time_range == label}>{label}</option>
              <% end %>
            </select>
          </form>

          <!-- Status Filter -->
          <form phx-change="filter_status" class="w-full lg:w-auto">
            <select
              id="status-filter"
              name="status"
              class="select select-bordered w-full lg:w-48"
              phx-change="filter_status"
            >
              <%= for {label, _value} <- @status_options do %>
                <option value={label} selected={@status_filter == label}>{label}</option>
              <% end %>
            </select>
          </form>
        </div>
      </div>

      <div class="mt-6 grid grid-cols-2 lg:grid-cols-4 gap-6">
        <.metric_card
          title="Total Requests"
          value={format_number(@summary_metrics.total_requests)}
          icon="message-circle"
        />
        <.metric_card
          title="Success Rate"
          value={format_percentage(@summary_metrics.success_rate)}
          icon="check-circle"
          value_class={success_rate_class(@summary_metrics.success_rate)}
        />
        <.metric_card
          title="Total Tokens"
          value={format_number(@summary_metrics.total_tokens)}
          icon="cpu"
        />
        <.metric_card
          title="Avg Response Time"
          value={format_response_time(@summary_metrics.avg_response_time)}
          icon="clock"
        />
      </div>

      <div class="mt-6">
        <%= if Enum.empty?(@all_models_stats) do %>
          <.empty_state />
        <% else %>
          <div class="bg-white shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Model Performance</h3>
              <.table rows={@all_models_stats} id="models-table">
                <:col :let={stats} label="Model">
                  <span class="font-medium text-gray-900">
                    {model_display_name(stats.model)}
                  </span>
                </:col>
                <:col :let={stats} label="Requests" align="right">
                  {format_number(stats.total_requests)}
                </:col>
                <:col :let={stats} label="Success Rate" align="center" class="hidden xl:table-cell">
                  <% success_rate =
                    if stats.total_requests > 0,
                      do: stats.successful_requests / stats.total_requests * 100,
                      else: 0 %>
                  <span class={success_rate_class(success_rate)}>
                    {format_percentage(success_rate)}
                  </span>
                </:col>
                <:col :let={stats} label="Avg Response Time" align="right" class="hidden xl:table-cell">
                  {format_response_time(stats.avg_response_time)}
                </:col>
                <:col :let={stats} label="Total Tokens" align="right" class="hidden xl:table-cell">
                  {format_number(stats.total_tokens)}
                </:col>
                <:col :let={stats} label="Errors" align="right">
                  <span class="text-red-600">
                    {format_number((stats.error_requests || 0) + (stats.timeout_requests || 0))}
                  </span>
                </:col>
              </.table>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @errors_result.total_count > 0 do %>
        <div class="mt-6">
          <div class="bg-white shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <div class="flex justify-between items-center mb-4">
                <h3 class="text-lg leading-6 font-medium text-gray-900">
                  Recent Errors
                  <span class="text-sm font-normal text-gray-500">
                    ({@errors_result.total_count} total
                    <%= if @errors_result.total_pages > 1 do %>
                      • Page {@errors_result.page} of {@errors_result.total_pages}
                      • Showing {(@errors_result.page - 1) * @errors_per_page + 1}-{min(@errors_result.page * @errors_per_page, @errors_result.total_count)}
                    <% end %>)
                  </span>
                </h3>
              </div>
              <.table rows={@errors_result.errors} id="errors-table">
                <:col :let={error} label="Status">
                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{status_badge_class(error.status)}"}>
                    {String.capitalize(error.status)}
                  </span>
                </:col>
                <:col :let={error} label="Model" class="hidden sm:table-cell">
                  {model_display_name(error.model)}
                </:col>
                <:col :let={error} label="Action" class="hidden md:table-cell">
                  {error.action}
                </:col>
                <:col :let={error} label="Error Message">
                  <span class="truncate max-w-xs" title={error.error_message}>
                    {String.slice(error.error_message || "", 0, 50)}{if String.length(error.error_message || "") > 50, do: "..."}
                  </span>
                </:col>
                <:col :let={error} label="Time" class="hidden lg:table-cell">
                  <span data-utc-time={error.inserted_at} id={"error-time-#{error.id}"} phx-hook="TimezoneDetector">
                    {format_datetime(error.inserted_at)}
                  </span>
                </:col>
                <:col :let={error} label="Actions" align="right">
                  <button
                    class="btn btn-outline btn-sm"
                    phx-click="view_error"
                    phx-value-error_id={error.id}
                  >
                    View Details
                  </button>
                </:col>
              </.table>

              <%= if @errors_result.total_pages > 1 do %>
                <div class="mt-4">
                  <!-- Mobile pagination (simplified) -->
                  <div class="flex sm:hidden justify-between items-center">
                    <%= if @errors_result.page > 1 do %>
                      <button
                        class="btn btn-outline btn-sm"
                        phx-click="paginate_errors"
                        phx-value-page={@errors_result.page - 1}
                      >
                        <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" />
                        Previous
                      </button>
                    <% else %>
                      <div></div>
                    <% end %>

                    <span class="text-sm text-gray-700">
                      Page {@errors_result.page} of {@errors_result.total_pages}
                    </span>

                    <%= if @errors_result.page < @errors_result.total_pages do %>
                      <button
                        class="btn btn-outline btn-sm"
                        phx-click="paginate_errors"
                        phx-value-page={@errors_result.page + 1}
                      >
                        Next
                        <.icon name="hero-arrow-right" class="w-4 h-4 ml-1" />
                      </button>
                    <% else %>
                      <div></div>
                    <% end %>
                  </div>

                  <!-- Desktop pagination (full) -->
                  <div class="hidden sm:block">
                    <div class="join w-full flex justify-center items-center">
                      <!-- First page button -->
                      <%= if @errors_result.page > 3 and @errors_result.total_pages > 5 do %>
                        <button class="join-item btn" phx-click="paginate_errors" phx-value-page={1}>
                          First
                        </button>
                        <%= if @errors_result.page > 4 do %>
                          <button class="join-item btn btn-disabled">...</button>
                        <% end %>
                      <% end %>

                      <!-- Previous page button -->
                      <%= if @errors_result.page > 1 do %>
                        <button class="join-item btn" phx-click="paginate_errors" phx-value-page={@errors_result.page - 1}>
                          <.icon name="hero-arrow-left" class="w-3.5 h-3.5" />
                        </button>
                      <% end %>

                      <!-- Page number buttons -->
                      <%= for page_num <- max(1, @errors_result.page - 2)..min(@errors_result.total_pages, @errors_result.page + 2) do %>
                        <button
                          class={"join-item btn #{if page_num == @errors_result.page, do: "btn-active"}"}
                          phx-click="paginate_errors"
                          phx-value-page={page_num}
                        >
                          {page_num}
                        </button>
                      <% end %>

                      <!-- Next page button -->
                      <%= if @errors_result.page < @errors_result.total_pages do %>
                        <button class="join-item btn" phx-click="paginate_errors" phx-value-page={@errors_result.page + 1}>
                          <.icon name="hero-arrow-right" class="w-3.5 h-3.5" />
                        </button>
                      <% end %>

                      <!-- Last page button -->
                      <%= if @errors_result.page < @errors_result.total_pages - 2 and @errors_result.total_pages > 5 do %>
                        <%= if @errors_result.page < @errors_result.total_pages - 3 do %>
                          <button class="join-item btn btn-disabled">...</button>
                        <% end %>
                        <button class="join-item btn" phx-click="paginate_errors" phx-value-page={@errors_result.total_pages}>
                          Last
                        </button>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <dialog id="error-details-modal" class={["modal", (@show_errors_drawer and @selected_error) && "modal-open"]}>
        <div class="modal-box max-w-2xl">
          <h3 class="font-bold text-lg">Error Details</h3>
          <p class="py-4">Detailed information about this AI error</p>
          <.error_details error={@selected_error} />
        </div>
        <form method="dialog" class="modal-backdrop" phx-click="close_errors_drawer">
          <button>close</button>
        </form>
      </dialog>
    </div>
    """
  end

  # Metric Card Component
  defp metric_card(assigns) do
    ~H"""
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <.metric_icon name={@icon} />
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">{@title}</dt>
              <dd class={"text-lg font-medium #{Map.get(assigns, :value_class, "text-gray-900")}"}>
                {@value}
              </dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp metric_icon(%{name: "message-circle"} = assigns) do
    ~H"""
    <.icon name="hero-chat-bubble-oval-left" class="h-6 w-6 text-gray-400" />
    """
  end

  defp metric_icon(%{name: "check-circle"} = assigns) do
    ~H"""
    <.icon name="hero-check-circle" class="h-6 w-6 text-green-400" />
    """
  end

  defp metric_icon(%{name: "cpu"} = assigns) do
    ~H"""
    <.icon name="hero-cpu-chip" class="h-6 w-6 text-blue-400" />
    """
  end

  defp metric_icon(%{name: "clock"} = assigns) do
    ~H"""
    <.icon name="hero-clock" class="h-6 w-6 text-yellow-400" />
    """
  end

  # Empty State Component
  defp empty_state(assigns) do
    ~H"""
    <div class="text-center py-12 bg-white shadow rounded-lg">
      <div class="mx-auto h-12 w-12 text-gray-400">
        <.icon name="hero-signal" class="h-12 w-12" />
      </div>
      <h3 class="mt-2 text-sm font-medium text-gray-900">No usage data found</h3>
      <p class="mt-1 text-sm text-gray-500">
        Start using AI features to see usage statistics here.
      </p>
    </div>
    """
  end



  # Error Details Component
  defp error_details(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <dt class="text-sm font-medium text-gray-500">Status</dt>
        <dd class="mt-1">
          <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{status_badge_class(@error.status)}"}>
            {String.capitalize(@error.status)}
          </span>
        </dd>
      </div>
      <div>
        <dt class="text-sm font-medium text-gray-500">Model</dt>
        <dd class="mt-1 text-sm text-gray-900">{model_display_name(@error.model)}</dd>
      </div>
      <div>
        <dt class="text-sm font-medium text-gray-500">Action</dt>
        <dd class="mt-1 text-sm text-gray-900">{@error.action}</dd>
      </div>
      <div>
        <dt class="text-sm font-medium text-gray-500">Error Message</dt>
        <dd class="mt-1 text-sm text-gray-900 bg-gray-50 p-3 rounded-md">
          {@error.error_message}
        </dd>
      </div>
      <div>
        <dt class="text-sm font-medium text-gray-500">Timestamp</dt>
        <dd class="mt-1 text-sm text-gray-900">
          <span data-utc-time={@error.inserted_at} id={"error-detail-time-#{@error.id}"} phx-hook="TimezoneDetector">
            {format_datetime(@error.inserted_at)}
          </span>
        </dd>
      </div>
      <%= if @error.user do %>
        <div>
          <dt class="text-sm font-medium text-gray-500">User</dt>
          <dd class="mt-1 text-sm text-gray-900">{@error.user.email}</dd>
        </div>
      <% end %>
      <%= if @error.response_time do %>
        <div>
          <dt class="text-sm font-medium text-gray-500">Response Time</dt>
          <dd class="mt-1 text-sm text-gray-900">{format_response_time(@error.response_time)}</dd>
        </div>
      <% end %>
      <%= if @error.metadata && map_size(@error.metadata) > 0 do %>
        <div>
          <dt class="text-sm font-medium text-gray-500">Metadata</dt>
          <dd class="mt-1 text-sm text-gray-900 bg-gray-50 p-3 rounded-md">
            <pre class="whitespace-pre-wrap"><%= Jason.encode!(@error.metadata, pretty: true) %></pre>
          </dd>
        </div>
      <% end %>
      <div class="mt-4 w-full">
        <button phx-click="close_errors_drawer" class="btn btn-outline w-full">Close</button>
      </div>
    </div>
    """
  end

  # Helper Functions
  defp build_url(socket, params) do
    current_params = %{
      model: socket.assigns.selected_model,
      time_range: socket.assigns.time_range,
      status: socket.assigns.status_filter,
      page: socket.assigns.page,
      errors_page: socket.assigns.errors_page
    }

    updated_params = Map.merge(current_params, params)

    query_string =
      updated_params
      |> Enum.reject(fn {_k, v} -> v == "All Models" or v == "All Status" or v == 1 end)
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("&")

    base_path = "/dashboard/super_admin/ai-timeline"
    if query_string == "", do: base_path, else: "#{base_path}?#{query_string}"
  end

  defp load_usage_data(socket) do
    time_range_label = socket.assigns.time_range
    selected_model = socket.assigns.selected_model
    status_filter_label = socket.assigns.status_filter
    errors_page = socket.assigns.errors_page
    errors_per_page = socket.assigns.errors_per_page

    # Convert time range label to numeric value for database queries
    time_range_days = get_time_range_days(time_range_label)

    # Convert status label to value for database queries
    status_filter_value = get_status_value(status_filter_label)

    # Use display name directly since that's what's stored in the database
    model_display_name = if selected_model != "All Models" do
      selected_model
    else
      nil
    end

    # Prepare filter options for usage stats
    stats_opts = [
      days: time_range_days,
      status: status_filter_value,
      model: model_display_name
    ]

    # Get overall filtered statistics
    all_models_stats = AI.get_usage_stats_filtered(stats_opts)

    # Get model-specific stats if a model is selected
    # Use display name since that's what's stored in the database
    model_stats =
      if selected_model != "All Models" do
        AI.get_model_usage_stats(selected_model, days: time_range_days)
      else
        nil
      end

    # Get timeline data for visualization
    # Use display name since that's what's stored in the database
    timeline_opts = [days: time_range_days]

    timeline_opts =
      if selected_model != "All Models" do
        Keyword.put(timeline_opts, :model, selected_model)
      else
        timeline_opts
      end

    timeline_data = AI.get_usage_timeline(timeline_opts)

    # Prepare filter options for error retrieval
    errors_opts = [
      page: errors_page,
      per_page: errors_per_page,
      days: time_range_days,
      model: model_display_name,
      status: case status_filter_value do
        "all" -> "all"  # Show all errors (error + timeout)
        "success" -> "error"  # Success filter should show errors for debugging
        other -> other  # error, timeout
      end
    ]

    # Get paginated and filtered errors
    errors_result = AI.get_errors_paginated(errors_opts)

    # Reset errors page if it's beyond available pages and update socket accordingly
    {errors_result, socket} =
      if errors_result.page > errors_result.total_pages and errors_result.total_pages > 0 do
        # Re-fetch with page 1
        updated_opts = Keyword.put(errors_opts, :page, 1)
        updated_result = AI.get_errors_paginated(updated_opts)
        updated_socket = assign(socket, :errors_page, 1)
        {updated_result, updated_socket}
      else
        {errors_result, socket}
      end

    # Calculate summary metrics based on filtered data
    summary_metrics = calculate_summary_metrics(all_models_stats)

    socket
    |> assign(:all_models_stats, all_models_stats)
    |> assign(:model_stats, model_stats)
    |> assign(:timeline_data, timeline_data)
    |> assign(:errors_result, errors_result)
    |> assign(:summary_metrics, summary_metrics)
    |> assign(:available_models, get_available_models(all_models_stats))
  end

  defp calculate_summary_metrics(all_models_stats) do
    total_requests = Enum.sum(Enum.map(all_models_stats, &to_number(&1.total_requests || 0)))
    total_successful = Enum.sum(Enum.map(all_models_stats, &to_number(&1.successful_requests || 0)))
    total_errors = Enum.sum(Enum.map(all_models_stats, &to_number(&1.error_requests || 0)))
    total_timeouts = Enum.sum(Enum.map(all_models_stats, &to_number(&1.timeout_requests || 0)))
    total_tokens = Enum.sum(Enum.map(all_models_stats, &to_number(&1.total_tokens || 0)))

    avg_response_times =
      all_models_stats
      |> Enum.map(& &1.avg_response_time)
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.map(&to_number/1)

    avg_response_time =
      if length(avg_response_times) > 0 do
        Enum.sum(avg_response_times) / length(avg_response_times)
      else
        0
      end

    success_rate = if total_requests > 0, do: total_successful / total_requests * 100, else: 0

    %{
      total_requests: total_requests,
      total_successful: total_successful,
      total_errors: total_errors + total_timeouts,  # Combine errors and timeouts
      total_tokens: total_tokens,
      success_rate: success_rate,
      avg_response_time: avg_response_time
    }
  end

  defp get_available_models(all_models_stats) do
    # Get display names instead of API IDs
    all_models_stats
    |> Enum.map(& &1.model)
    |> Enum.map(&AI.Models.get_display_name/1)
    |> Enum.reject(&(&1 == "All Models"))
  end

  defp get_time_range_days(time_range_label) do
    case time_range_label do
      "Last 7 days" -> 7
      "Last 30 days" -> 30
      "Last 90 days" -> 90
      "Last year" -> 365
      # Fallback for numeric values (backward compatibility)
      value when is_integer(value) -> value
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int_value, ""} -> int_value
          _ -> 30  # Default to 30 days
        end
      _ -> 30  # Default to 30 days
    end
  end

  defp get_status_value(status_label) do
    case status_label do
      "All Status" -> "all"
      "Success" -> "success"
      "Error" -> "error"
      "Timeout" -> "timeout"
      # Fallback for existing values (backward compatibility)
      value when is_binary(value) -> value
      _ -> "all"  # Default to all
    end
  end

  # Helper function to convert Decimal values to numbers
  defp to_number(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_number(number) when is_number(number), do: number
  defp to_number(_), do: 0

  defp format_number(nil), do: "0"
  defp format_number(%Decimal{} = decimal), do: format_number(Decimal.to_float(decimal))

  defp format_number(number) when is_float(number) do
    if number == trunc(number) do
      format_number(trunc(number))
    else
      :erlang.float_to_binary(number, decimals: 2)
    end
  end

  defp format_number(number) when is_integer(number) do
    number
    |> to_string()
    |> String.reverse()
    |> String.codepoints()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(number), do: to_string(number)

  defp format_percentage(nil), do: "0%"
  defp format_percentage(%Decimal{} = decimal), do: format_percentage(Decimal.to_float(decimal))

  defp format_percentage(percentage) when is_float(percentage) do
    :erlang.float_to_binary(percentage, decimals: 1) <> "%"
  end

  defp format_percentage(percentage), do: "#{percentage}%"

  defp format_response_time(nil), do: "0ms"
  defp format_response_time(%Decimal{} = decimal), do: format_response_time(Decimal.to_float(decimal))

  defp format_response_time(time) when is_float(time) do
    :erlang.float_to_binary(time, decimals: 0) <> "ms"
  end

  defp format_response_time(time), do: "#{time}ms"

  defp model_display_name(model) do
    AI.Models.get_display_name(model)
  end

  defp format_datetime(datetime) do
    case datetime do
      %DateTime{} ->
        # Use UTC time for server-side display, client-side hook will convert to local time
        Calendar.strftime(datetime, "%m/%d/%Y %I:%M %p UTC")

      %NaiveDateTime{} ->
        # Convert naive datetime to UTC first
        datetime
        |> DateTime.from_naive!("Etc/UTC")
        |> Calendar.strftime("%m/%d/%Y %I:%M %p UTC")

      _ ->
        "N/A"
    end
  end

  defp success_rate_class(rate) when rate >= 95, do: "text-green-600"
  defp success_rate_class(rate) when rate >= 90, do: "text-yellow-600"
  defp success_rate_class(_), do: "text-red-600"

  defp status_badge_class("success"), do: "bg-green-100 text-green-800"
  defp status_badge_class("error"), do: "bg-red-100 text-red-800"
  defp status_badge_class("timeout"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end
