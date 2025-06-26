defmodule Public.UserRegistrationLive do
  @moduledoc """
  LiveView for user registration and account creation.

  This view provides a registration form for new users to create accounts with
  email and password. It handles form validation, account creation, and sending
  confirmation emails. After successful registration, users are redirected to the
  login page with a success message.
  """
  use Public, :live_view

  alias Core.Accounts
  alias Core.Accounts.User
  alias Public.PageMeta

  @doc """
  Renders the registration form.

  Displays a form with email and password fields for account creation,
  along with a link to the login page for existing users.
  """
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-full">
      <div class="w-full max-w-sm mt-64 lg:mt-0">
        <.header class="text-center">
          Register for an account
          <:subtitle>
            Already registered?
            <.link navigate={~p"/login"} class="font-semibold text-brand hover:underline">
              Log in
            </.link>
            to your account now.
          </:subtitle>
        </.header>

        <form
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
          action={@login_path}
          method="post"
        >
          <input name="_csrf_token" type="hidden" value={@csrf_token} />
          <.error :if={@check_errors}>
            Oops, something went wrong! Please check the errors below.
          </.error>
          <fieldset class="fieldset w-full">
            <input class="input text-base w-full" name={@form[:email].name} id={@form[:email].id} value={@form[:email].value} type="email" placeholder="your@email.com" required />
            <input class="input text-base w-full" name={@form[:password].name} id={@form[:password].id} value={@form[:password].value} type="password" placeholder="********" required />

            <button phx-disable-with="Creating account..." class="btn btn-primary mt-4 w-full">Create an account</button>
          </fieldset>
        </form>
      </div>
    </div>
    """
  end

  @spec mount(nil | maybe_improper_list() | map(), any(), any()) ::
          {:ok, any(), [{:temporary_assigns, [...]}, ...]}
  @doc """
  Initializes the LiveView with an empty registration form and page metadata.

  Sets up the initial changeset for user registration, configures page metadata
  with appropriate title and description, and initializes form state variables.
  """
  def mount(params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    # Store the plan_id from URL parameters
    selected_plan_id = params["plan_id"]

    # Set the default login path based on whether we have a plan_id
    login_path =
      if selected_plan_id do
        ~p"/login?_action=registered&plan_id=#{selected_plan_id}"
      else
        ~p"/login?_action=registered"
      end

    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "Register",
        description: "Create a new account",
        url: "/register"
      )
      |> assign(trigger_submit: false, check_errors: false)
      |> assign(selected_plan_id: selected_plan_id)
      |> assign(login_path: login_path)
      |> assign(csrf_token: Plug.CSRFProtection.get_csrf_token())
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @doc """
  Handles form submission for user registration.

  Processes the registration data, attempts to create a new user account,
  sends a confirmation email, and redirects to the login page on success.
  If there are validation errors, redisplays the form with error messages.
  """
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/confirm/#{&1}")
          )

        # Add the selected plan ID as a URL parameter when redirecting to login
        # instead of trying to modify the session directly from LiveView
        login_path =
          if socket.assigns[:selected_plan_id] do
            ~p"/login?_action=registered&plan_id=#{socket.assigns.selected_plan_id}"
          else
            ~p"/login?_action=registered"
          end

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign(login_path: login_path) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
