defmodule Admin.PlatformSettingsLive do
  @moduledoc """
  LiveView for managing platform-wide settings.

  This view allows super admins to configure platform-wide settings
  such as enabling/disabling subscriptions and single purchase products.
  """
  use Admin, :live_view
  alias Core.Subscriptions
  alias Admin.PageMeta
  alias Core.PubSub.DataSync
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("platform_settings", "all")
    end

    platform_settings = Subscriptions.list_platform_settings()

    {:ok,
     socket
     |> assign(:platform_settings, platform_settings)
     |> assign(:loading, false)
     |> PageMeta.assign_metadata(
       title: "Platform Settings",
       description: "Configure platform-wide settings and features",
       url: "/dashboard/platform-settings"
     )}
  end

  @impl true
  def handle_event("toggle_setting", %{"key" => key}, socket) do
    current_user = socket.assigns.current_user

    # Find the current setting and toggle its value
    current_setting = Enum.find(socket.assigns.platform_settings, &(&1.key == key))
    new_value = if current_setting, do: !current_setting.value, else: true

    socket = assign(socket, :loading, true)

    # Debug output
    IO.inspect({key, current_setting && current_setting.value, new_value}, label: "Toggle setting")

    case Subscriptions.update_platform_setting(key, new_value, current_user) do
      {:ok, _setting} ->
        platform_settings = Subscriptions.list_platform_settings()

        {:noreply,
         socket
         |> assign(:platform_settings, platform_settings)
         |> assign(:loading, false)
         |> put_flash(:info, "Platform setting updated successfully")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "You are not authorized to modify platform settings")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Platform setting not found")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Failed to update platform setting")}
    end
  end

  @impl true
  def handle_event("seed_database", _params, socket) do
    current_user = socket.assigns.current_user

    Logger.info("Database seeding requested by user: #{current_user.email}")

    # Run seeding as a supervised task using our simplified seeder
    Task.Supervisor.start_child(Core.TaskSupervisor, fn ->
      case Core.Tasks.Seeder.create_essential_data() do
        {:ok, :completed} ->
          Logger.info("✅ Database seeding completed successfully")
        {:error, reason} ->
          Logger.error("❌ Database seeding failed: #{inspect(reason)}")
      end
    end)

    {:noreply,
     socket
     |> put_flash(:info, "Database seeding started! Creating essential test data with direct database calls. Check the logs for progress.")}
  end

  @impl true
  def handle_info({:updated, %{type: :platform_setting}}, socket) do
    # Reload settings when updated via PubSub
    platform_settings = Subscriptions.list_platform_settings()
    {:noreply, assign(socket, :platform_settings, platform_settings)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1">
      <.header>
        Platform Settings
        <:subtitle>Configure platform-wide features and settings</:subtitle>
      </.header>

      <div class="mt-8 max-w-4xl">
        <div class="bg-base-100 shadow rounded-lg">
          <div class="px-6 py-4 border-b border-base-300">
            <h3 class="text-lg font-medium text-base-content">Product Types</h3>
            <p class="mt-1 text-sm text-base-content/70">
              Control which product types are available across the platform
            </p>
          </div>

          <div class="px-6 py-4 space-y-6">
            <%= for setting <- @platform_settings do %>
              <div class="flex items-center justify-between">
                <div class="flex-1">
                  <h4 class="text-sm font-medium text-base-content">
                    {format_setting_title(setting.key)}
                  </h4>
                  <p class="text-sm text-base-content/70">
                    {setting.description}
                  </p>
                </div>
                                <div class="ml-6">
                  <input
                    type="checkbox"
                    class="toggle toggle-primary"
                    phx-click="toggle_setting"
                    phx-value-key={setting.key}
                    disabled={@loading}
                    checked={setting.value}
                  />
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="mt-8 grid grid-cols-1 md:grid-cols-2 gap-6">
          <%= for setting <- @platform_settings do %>
            <div class={[
              "border rounded-lg p-4",
              if(setting.value,
                do: "border-success/20 bg-success/10",
                else: "border-base-300 bg-base-200"
              )
            ]}>
              <div class="flex items-center justify-between">
                <h4 class="text-sm font-medium text-base-content">
                  {format_setting_title(setting.key)}
                </h4>
                <span class={[
                  "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                  if(setting.value,
                    do: "badge badge-success",
                    else: "badge badge-ghost"
                  )
                ]}>
                  {if setting.value, do: "Enabled", else: "Disabled"}
                </span>
              </div>
              <p class="mt-2 text-xs text-base-content/70">
                Last updated: {Calendar.strftime(setting.updated_at, "%B %d, %Y at %H:%M")}
              </p>
            </div>
          <% end %>
        </div>

        <!-- Database Management Section -->
        <div class="mt-8 bg-base-100 shadow rounded-lg">
          <div class="px-6 py-4 border-b border-base-300">
            <h3 class="text-lg font-medium text-base-content">Database Management</h3>
            <p class="mt-1 text-sm text-base-content/70">
              Manage database content and seeding operations
            </p>
          </div>

          <div class="px-6 py-4">
            <div class="flex items-center justify-between">
              <div class="flex-1">
                <h4 class="text-sm font-medium text-base-content">
                  Create Test Data
                </h4>
                <p class="text-sm text-base-content/70">
                  Create essential test data including subscription plans, users, blog posts, and more.
                  Safe for production - only creates data that doesn't already exist.
                </p>
              </div>
              <div class="ml-6">
                <button
                  type="button"
                  phx-click="seed_database"
                  disabled={@loading}
                  class="btn btn-primary"
                >
                  <.icon name="hero-circle-stack" class="w-4 h-4 mr-2" />
                  Create Test Data
                </button>
              </div>
            </div>

          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper function to format setting keys into readable titles
  defp format_setting_title(key) do
    key
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
