defmodule Public.Onboarding.ProfileLive do
  @moduledoc """
  LiveView for the user profile onboarding process.

  This view allows new users to complete their profile information as part of the
  onboarding flow. It provides a form for entering personal details like name,
  contact information, and bio, and handles saving this information to the database.
  Upon successful completion, users are redirected to the dashboard.
  """
  use Public, :live_view

  alias Core.Accounts
  alias Core.Accounts.Profile
  alias Public.PageMeta
  alias Core.Subscriptions

  @doc """
  Renders the profile onboarding form with success modal when applicable.

  Displays a form for collecting the user's profile information, along with
  appropriate validation and submission handling. Shows a success modal after
  successful completion of the onboarding process.
  """
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-16 px-4">
      <.modal :if={@show_success} id="success-modal" show>
        <div class="text-center">
          <div class="mx-auto flex items-center justify-center h-16 w-16 rounded-full bg-success/20 mb-4">
            <.icon name="hero-check-circle" class="h-8 w-8 text-success" />
          </div>
          <.header>
            Onboarding Complete!
            <:subtitle>
              Thank you for setting up your profile.
              <%= if @has_selected_plan do %>
                Redirecting to complete your subscription...
              <% else %>
                Redirecting to dashboard...
              <% end %>
            </:subtitle>
          </.header>
        </div>
      </.modal>

      <div class="mb-8 flex justify-center">
        <div class="h-12 w-12 rounded-full bg-primary/20 flex items-center justify-center">
          <.icon name="hero-user" class="h-6 w-6 text-primary" />
        </div>
      </div>
      <.header class="text-center">
        Complete Your Profile
        <:subtitle>
          Let's set up your profile information to get started
        </:subtitle>
      </.header>

      <form id="profile_form" phx-submit="save" phx-change="validate" class="space-y-6">
        <.error :if={@check_errors}>
          Oops, something went wrong! Please check the errors below.
        </.error>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="form-control w-full">
            <label class="label">
              <span class="label-text">First Name</span>
            </label>
            <input
              type="text"
              name={@form[:first_name].name}
              id={@form[:first_name].id}
              value={@form[:first_name].value}
              class="input input-bordered w-full"
              placeholder="John"
              required
            />
          </div>
          <div class="form-control w-full">
            <label class="label">
              <span class="label-text">Last Name</span>
            </label>
            <input
              type="text"
              name={@form[:last_name].name}
              id={@form[:last_name].id}
              value={@form[:last_name].value}
              class="input input-bordered w-full"
              placeholder="Doe"
              required
            />
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="form-control w-full">
            <label class="label">
              <span class="label-text">Phone</span>
            </label>
            <input
              type="text"
              name={@form[:phone].name}
              id={@form[:phone].id}
              value={@form[:phone].value}
              class="input input-bordered w-full"
              placeholder="123-456-7890"
              required
            />
          </div>
          <div class="form-control w-full">
            <label class="label">
              <span class="label-text">Location</span>
            </label>
            <input
              type="text"
              name={@form[:location].name}
              id={@form[:location].id}
              value={@form[:location].value}
              class="input input-bordered w-full"
              placeholder="New York"
              required
            />
          </div>
        </div>

        <div class="form-control w-full">
          <label class="label">
            <span class="label-text">Bio</span>
          </label>
          <textarea
            name={@form[:bio].name}
            id={@form[:bio].id}
            class="textarea textarea-bordered w-full"
            placeholder="Tell us about yourself"
            rows="4"
          ><%= @form[:bio].value %></textarea>
        </div>

        <button type="submit" phx-disable-with="Saving..." class="btn btn-primary w-full">
          Save Profile
        </button>
      </form>
    </div>
    """
  end

  @doc """
  Initializes the LiveView with either an existing or new profile form.

  Checks if the user already has a profile and loads that data if available,
  or initializes a new profile form if not. Sets up page metadata and initializes
  state for error checking and success modal.
  """
  def mount(params, session, socket) do
    user = socket.assigns.current_user

    # Check if user already has a profile
    profile =
      case Accounts.get_profile_by_user_id(user.id) do
        nil -> %Profile{user_id: user.id}
        existing -> existing
      end

    changeset = Accounts.change_profile(profile)

    # Check if there's a selected plan in the URL params first, then fall back to session
    # This ensures we prioritize the plan_id in the URL over session
    plan_id_from_params = params["plan_id"]
    plan_id_from_session = session["selected_plan_id"]
    selected_plan_id = plan_id_from_params || plan_id_from_session

    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "Complete Your Profile",
        description: "Set up your profile information to get started",
        url: "/onboarding/profile"
      )
      |> assign(:check_errors, false)
      |> assign(:show_success, false)
      |> assign(:selected_plan_id, selected_plan_id)
      |> assign(:has_selected_plan, not is_nil(selected_plan_id))
      |> assign_form(changeset)

    {:ok, socket}
  end

  def handle_info(:redirect_after_onboarding, socket) do
    # Check if user selected a plan during registration
    case socket.assigns.selected_plan_id do
      nil ->
        # No plan selected, redirect to home page (dashboard not implemented yet)
        {:noreply, push_navigate(socket, to: ~p"/")}

      plan_id ->
        # Plan selected, initiate Stripe checkout
        user = socket.assigns.current_user
        plan = Subscriptions.get_plan!(plan_id)

        case Subscriptions.change_subscription_plan(user, plan) do
          {:ok, %Stripe.Session{url: checkout_url}} ->
            # Redirect to Stripe checkout
            {:noreply, redirect(socket, external: checkout_url)}

          {:error, _error} ->
            # On error, redirect to home page with error message (dashboard not implemented yet)
            {:noreply,
             socket
             |> put_flash(:error, "Failed to process subscription. Please try again later.")
             |> push_navigate(to: ~p"/")}
        end
    end
  end

  def handle_event("validate", %{"profile" => profile_params}, socket) do
    changeset =
      socket.assigns.current_user.id
      |> Accounts.get_profile_by_user_id()
      |> case do
        nil -> %Profile{user_id: socket.assigns.current_user.id}
        profile -> profile
      end
      |> Accounts.change_profile(profile_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"profile" => profile_params}, socket) do
    user = socket.assigns.current_user

    # Check if user already has a profile
    save_profile(user, profile_params, socket)
  end

  defp save_profile(user, profile_params, socket) do
    case Accounts.get_profile_by_user_id(user.id) do
      nil ->
        # Create new profile
        case Accounts.create_profile(user, profile_params) do
          {:ok, _profile} ->
            # Mark onboarding as completed
            {:ok, _updated_user} = Accounts.complete_onboarding(user)

            # Show success modal and schedule redirect
            Process.send_after(self(), :redirect_after_onboarding, 2000)
            {:noreply, assign(socket, show_success: true)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, check_errors: true) |> assign_form(changeset)}
        end

      profile ->
        # Update existing profile
        case Accounts.update_profile(profile, profile_params) do
          {:ok, _profile} ->
            # Mark onboarding as completed
            {:ok, _updated_user} = Accounts.complete_onboarding(user)

            # Show success modal and schedule redirect
            Process.send_after(self(), :redirect_after_onboarding, 2000)
            {:noreply, assign(socket, show_success: true)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, check_errors: true) |> assign_form(changeset)}
        end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "profile")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
