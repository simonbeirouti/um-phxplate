defmodule Public.Dashboard.UserAccountLive do
  @moduledoc """
  LiveView for managing all aspects of a user's account.

  This view provides a tabbed interface for users to manage their profile information,
  subscription details, account settings, and view their activity history. It serves
  as a container for more specialized components that handle each area of functionality.
  """
  use Public, :live_view
  alias Public.Dashboard.Account.{SettingsLive, BillingLive}
  alias Public.Components.Upload.ImageUploadComponent
  alias Public.Components.ActivityTimelineComponent
  alias Core.{Repo, Accounts}
  alias Public.PageMeta
  require Logger

  @social_networks [:github, :twitter, :linkedin, :facebook, :instagram]

  @tab_titles %{
    "profile" => %{
      title: "User Profile",
      subtitle: "Manage your personal information and profile settings"
    },
    "subscription" => %{
      title: "Subscription Management",
      subtitle: "View and manage your subscription plans and billing information"
    },
    "settings" => %{
      title: "Account Settings",
      subtitle: "Configure your account preferences and security settings"
    },
    "activities" => %{
      title: "Account Activities",
      subtitle: "View your recent account activities and login history"
    }
  }

  @doc """
  Initializes the LiveView with user data and available tabs.

  Loads the user's profile, subscription and activity data, and
  sets up the default tab.
  """
  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to platform settings changes and plan changes for the billing component
    if connected?(socket) do
      Core.PubSub.DataSync.subscribe("platform_settings", "all")
      Core.PubSub.DataSync.subscribe("plans", "all")
    end

    user = socket.assigns.current_user |> Repo.preload([:profile, :subscription])
    activities = Core.Tracking.get_user_activities(user.id, 20)

    # Get initial tab titles
    %{subtitle: initial_subtitle} = get_tab_titles("profile")

    # Get the existing profile or create a new one
    profile = user.profile || %Accounts.Profile{user_id: user.id}
    changeset = Accounts.change_profile(profile)

    # Extract social links from profile or use empty map
    social_links = profile.social_links || %{}

    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "User Account",
        description: "Manage your user profile, billing, settings and account activity",
        url: "/dashboard/account"
      )
      |> assign(:user, user)
      |> assign(:activities, activities)
      |> assign(:page_subtitle, initial_subtitle)
      |> assign(:form, to_form(changeset))
      |> assign(:social_links, social_links)
      |> assign(:social_networks, @social_networks)
      |> assign(:form_changed, false)
      # Default selected tab
      |> assign(:selected_tab, "profile")
      # Initialize layout_data for navigation
      |> assign(:layout_data, %{current_path: "/dashboard/account"})

    {:ok, socket}
  end

  @doc """
  Handles URL parameters to determine the active tab.

  Updates the header subtitle based on the selected tab.
  """
  @impl true
  def handle_params(%{"token" => token}, _url, socket) do
    case Accounts.update_user_email(socket.assigns.current_user, token) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Email changed successfully.")
         |> push_navigate(to: ~p"/dashboard/account?tab=settings")}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Email change link is invalid or it has expired.")
         |> push_navigate(to: ~p"/dashboard/account?tab=settings")}
    end
  end

  def handle_params(params, url, socket) do
    # Update current path for breadcrumbs and layout component
    uri = URI.parse(url)
    socket = update(socket, :layout_data, &Map.put(&1, :current_path, uri.path))

    # Update the layout component with the new path
    send_update(Public.Dashboard.LayoutComponent,
      id: "dashboard-layout",
      current_path: uri.path
    )

    # Get the tab from params or default to "profile"
    tab = Map.get(params, "tab", "profile")

    # Ensure that the tab is valid or fallback to "profile"
    tab =
      if tab in ["profile", "subscription", "settings", "activities"], do: tab, else: "profile"

    %{subtitle: subtitle} = get_tab_titles(tab)

    {:noreply,
     socket
     |> assign(:page_subtitle, subtitle)
     |> assign(:selected_tab, tab)}
  end

  @impl true
  def handle_event("close_dialog", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("tab_changed", %{"tab" => tab}, socket) do
    %{subtitle: subtitle} = get_tab_titles(tab)

    {:noreply,
     socket
     |> assign(:page_subtitle, subtitle)
     |> assign(:selected_tab, tab)
     |> push_patch(to: ~p"/dashboard/account?tab=#{tab}", replace: true)}
  end

  @impl true
  def handle_event("validate", %{"profile" => profile_params}, socket) do
    # Get original profile data for comparison
    profile = socket.assigns.user.profile || %Accounts.Profile{user_id: socket.assigns.user.id}

    original_data = %{
      "first_name" => profile.first_name || "",
      "last_name" => profile.last_name || "",
      "phone" => profile.phone || "",
      "location" => profile.location || "",
      "bio" => profile.bio || "",
      "website" => profile.website || ""
    }

    # Add social links to original data
    original_social_data =
      @social_networks
      |> Enum.reduce(%{}, fn network, acc ->
        social_key = "social_links_#{network}"

        social_value =
          if profile.social_links,
            do: profile.social_links[Atom.to_string(network)] || "",
            else: ""

        Map.put(acc, social_key, social_value)
      end)

    original_data = Map.merge(original_data, original_social_data)

    # Check if form has changed
    form_changed = profile_params != original_data

    changeset =
      Accounts.change_profile(profile, profile_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset), form_changed: form_changed)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("reset_profile", _params, socket) do
    profile = socket.assigns.user.profile || %Accounts.Profile{user_id: socket.assigns.user.id}
    changeset = Accounts.change_profile(profile)
    social_links = profile.social_links || %{}

    {:noreply,
     assign(socket, form: to_form(changeset), form_changed: false, social_links: social_links)}
  end

  @impl true
  def handle_event("save", params, socket) do
    if Map.has_key?(params, "profile") do
      handle_profile_save(socket, params["profile"])
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:flash_msg, type, message}, socket) do
    {:noreply, put_flash(socket, type, message)}
  end

  @impl true
  def handle_info({:image_uploaded, %{type: :avatar, url: url, old_url: _old_url}}, socket) do
    # Create a profile update map with only the avatar_url field
    profile_update = %{"avatar_url" => url}

    case Accounts.update_profile(socket.assigns.user.profile, profile_update) do
      {:ok, updated_profile} ->
        user = %{socket.assigns.user | profile: updated_profile}

        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:form, to_form(Accounts.change_profile(updated_profile)))
         |> put_flash(:info, "Avatar uploaded successfully")}

      {:error, _changeset} ->
        # If the profile update failed, try to delete the new image to avoid orphaned files
        if url do
          Task.start(fn -> Core.AWS.S3.delete_file(url) end)
        end

        {:noreply,
         socket
         |> put_flash(:error, "Failed to update profile with new avatar")}
    end
  end

  @impl true
  def handle_info({:image_uploaded_error, %{error: error_msg}}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, error_msg)}
  end

  # Handle platform settings updates and forward to billing component
  @impl true
  def handle_info({:updated, %{type: :platform_setting}} = msg, socket) do
    # Forward the message to the billing component
    send_update(BillingLive, id: "user_billing", platform_settings_updated: msg)
    {:noreply, socket}
  end

  # Handle plan updates and forward to billing component
  @impl true
  def handle_info({:created, %{type: :plan}} = msg, socket) do
    # Forward the message to the billing component
    send_update(BillingLive, id: "user_billing", plans_updated: msg)
    {:noreply, socket}
  end

  def handle_info({:updated, %{type: :plan}} = msg, socket) do
    # Forward the message to the billing component
    send_update(BillingLive, id: "user_billing", plans_updated: msg)
    {:noreply, socket}
  end

  def handle_info({:deleted, %{type: :plan}} = msg, socket) do
    # Forward the message to the billing component
    send_update(BillingLive, id: "user_billing", plans_updated: msg)
    {:noreply, socket}
  end

  # Catch-all for other PubSub messages we don't need to handle
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp handle_profile_save(socket, profile_params) do
    profile_params = clean_params(profile_params)
    social_links = extract_social_links(profile_params)
    profile_params = Map.put(profile_params, "social_links", social_links)

    case Accounts.update_user_profile(socket.assigns.user, profile_params) do
      {:ok, updated_profile} ->
        user = %{socket.assigns.user | profile: updated_profile}

        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:social_links, social_links)
         |> assign(:form, to_form(Accounts.change_profile(updated_profile)))
         |> assign(:form_changed, false)
         |> put_flash(:info, "Profile updated successfully!")}

      {:error, changeset} ->
        error_message =
          case changeset.errors do
            [] ->
              "Failed to update profile. Please check your input and try again."

            errors ->
              errors
              |> Enum.map(fn {field, {msg, _}} ->
                "#{Phoenix.Naming.humanize(field)} #{msg}"
              end)
              |> Enum.join(". ")
          end

        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, error_message)}
    end
  end

  defp clean_params(params) do
    params
    |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "_unused_") end)
    |> Map.new()
  end

  defp extract_social_links(params) do
    @social_networks
    |> Enum.reduce(%{}, fn network, acc ->
      case params["social_links_#{network}"] do
        url when is_binary(url) and url != "" ->
          Map.put(acc, Atom.to_string(network), url)

        _ ->
          acc
      end
    end)
  end

  defp get_tab_titles(tab) do
    Map.get(@tab_titles, tab, %{
      title: "User Profile",
      subtitle: "Manage your user profile, billing, settings and account activity"
    })
  end

  @doc """
  Renders the user account page with tabbed interface.

  Displays tabs for profile, subscription, settings, and activities,
  and renders the appropriate component for the selected tab.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]">
      <.header>
        {get_tab_titles(@selected_tab).title}
        <:subtitle>{@page_subtitle}</:subtitle>
      </.header>

      <div class="mt-4">
        <!-- DaisyUI Tabs with Radio Inputs -->
        <div class="tabs tabs-lift">
          <!-- Profile Tab -->
          <input
            type="radio"
            name="account_tabs"
            class="tab"
            aria-label="Profile"
            checked={@selected_tab == "profile"}
            phx-click="tab_changed"
            phx-value-tab="profile"
          />
          <div class="tab-content bg-base-100 border-base-300 rounded-box p-6">
            <div class="space-y-6">
              <div class="flex flex-col items-center gap-4 mb-6">
                <.live_component
                  module={ImageUploadComponent}
                  id="profile-avatar"
                  type={:avatar}
                  image_url={@user.profile.avatar_url}
                  entity_type={:user}
                  entity_id={@user.id}
                  on_upload_complete="image_uploaded"
                />
              </div>

              <form
                id="profile-form"
                phx-change="validate"
                phx-submit="save"
                class="form-control space-y-4"
              >
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">First Name</span>
                    </label>
                    <input
                      type="text"
                      name={@form[:first_name].name}
                      id={@form[:first_name].id}
                      value={@form[:first_name].value}
                      placeholder="John"
                      class="input input-bordered w-full text-base"
                    />
                    <div :for={msg <- @form[:first_name].errors} class="label">
                      <span class="label-text-alt text-error">{msg}</span>
                    </div>
                  </div>

                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">Last Name</span>
                    </label>
                    <input
                      type="text"
                      name={@form[:last_name].name}
                      id={@form[:last_name].id}
                      value={@form[:last_name].value}
                      placeholder="Doe"
                      class="input input-bordered w-full text-base"
                    />
                    <div :for={msg <- @form[:last_name].errors} class="label">
                      <span class="label-text-alt text-error">{msg}</span>
                    </div>
                  </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">Phone Number</span>
                    </label>
                    <input
                      type="tel"
                      name={@form[:phone].name}
                      id={@form[:phone].id}
                      value={@form[:phone].value}
                      placeholder="123-456-7890"
                      class="input input-bordered w-full text-base"
                    />
                    <div :for={msg <- @form[:phone].errors} class="label">
                      <span class="label-text-alt text-error">{msg}</span>
                    </div>
                  </div>

                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-medium">Location</span>
                    </label>
                    <input
                      type="text"
                      name={@form[:location].name}
                      id={@form[:location].id}
                      value={@form[:location].value}
                      placeholder="New York"
                      class="input input-bordered w-full text-base"
                    />
                    <div :for={msg <- @form[:location].errors} class="label">
                      <span class="label-text-alt text-error">{msg}</span>
                    </div>
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Bio</span>
                  </label>
                  <textarea
                    name={@form[:bio].name}
                    id={@form[:bio].id}
                    placeholder="Tell us about yourself"
                    class="textarea textarea-bordered w-full text-base"
                    rows="4"
                  >{@form[:bio].value}</textarea>
                  <div :for={msg <- @form[:bio].errors} class="label">
                    <span class="label-text-alt text-error">{msg}</span>
                  </div>
                </div>

                <div class="space-y-4">
                  <label class="label">
                    <span class="label-text font-medium text-lg">Links</span>
                  </label>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="form-control">
                      <label class="label">
                        <span class="label-text font-medium">Website</span>
                      </label>
                      <input
                        type="url"
                        name={@form[:website].name}
                        id={@form[:website].id}
                        value={@form[:website].value}
                        placeholder="https://www.yourwebsite.com"
                        class="input input-bordered w-full text-base"
                      />
                      <div :for={msg <- @form[:website].errors} class="label">
                        <span class="label-text-alt text-error">{msg}</span>
                      </div>
                    </div>

                    <%= for network <- @social_networks do %>
                      <div class="form-control">
                        <label class="label">
                          <span class="label-text font-medium">{Phoenix.Naming.humanize(network)}</span>
                        </label>
                        <input
                          type="url"
                          name={"profile[social_links_#{network}]"}
                          value={@social_links[Atom.to_string(network)]}
                          placeholder={"Your #{Phoenix.Naming.humanize(network)} URL"}
                          class="input input-bordered w-full text-base"
                        />
                      </div>
                    <% end %>
                  </div>
                </div>

                <%= if @form_changed do %>
                  <div class="flex flex-col gap-3 lg:flex-row lg:gap-3 pt-6">
                    <button
                      type="button"
                      phx-click="reset_profile"
                      class="btn btn-outline w-full lg:w-auto"
                    >
                      Reset
                    </button>
                    <button
                      type="submit"
                      phx-disable-with="Saving..."
                      class="btn btn-primary w-full lg:w-auto"
                    >
                      Save Changes
                    </button>
                  </div>
                <% end %>
              </form>
            </div>
          </div>

          <!-- Subscription Tab -->
          <input
            type="radio"
            name="account_tabs"
            class="tab"
            aria-label="Subscription"
            checked={@selected_tab == "subscription"}
            phx-click="tab_changed"
            phx-value-tab="subscription"
          />
          <div class="tab-content bg-base-100 border-base-300 rounded-box p-6">
            <.live_component module={BillingLive} id="user_billing" user={@user} />
          </div>

          <!-- Settings Tab -->
          <input
            type="radio"
            name="account_tabs"
            class="tab"
            aria-label="Settings"
            checked={@selected_tab == "settings"}
            phx-click="tab_changed"
            phx-value-tab="settings"
          />
          <div class="tab-content bg-base-100 border-base-300 rounded-box p-6">
            <.live_component module={SettingsLive} id="user_settings" user={@user} />
          </div>

          <!-- Activities Tab -->
          <input
            type="radio"
            name="account_tabs"
            class="tab"
            aria-label="Activities"
            checked={@selected_tab == "activities"}
            phx-click="tab_changed"
            phx-value-tab="activities"
          />
          <div class="tab-content bg-base-100 border-base-300 rounded-box p-6">
            <.live_component
              module={ActivityTimelineComponent}
              id={"activity-timeline-#{@user.id}"}
              activities={@activities}
              user_id={@user.id}
              show_timestamps={false}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
