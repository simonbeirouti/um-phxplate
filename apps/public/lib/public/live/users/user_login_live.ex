defmodule Public.UserLoginLive do
  @moduledoc """
  LiveView for user authentication login.

  This view provides a login form for users to authenticate with email and password.
  It includes a "remember me" option and links to registration and password reset.
  The form submission is processed by the standard Phoenix controller action,
  not within the LiveView.
  """
  use Public, :live_view
  alias Public.PageMeta

  @doc """
  Renders the login form.

  Displays a form with email and password fields, "remember me" checkbox,
  and links to registration and password reset pages.
  """
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-full">
      <div class="w-full max-w-sm mt-64 lg:mt-0">
        <.header class="text-center">
          Log in to account
          <:subtitle>
            Don't have an account?
            <.link navigate={~p"/register"} class="font-semibold text-brand hover:underline">
              Sign up
            </.link>
            for an account now.
          </:subtitle>
        </.header>

        <form class="form-control" phx-change="validate" id="login_form" action={~p"/login"} method="post" phx-update="ignore">
          <input name="_csrf_token" type="hidden" value={@csrf_token} />
          <fieldset class="fieldset w-full">
            <input class="input w-full text-base" placeholder="your@email.com" name={@form[:email].name} id={@form[:email].id} value={@form[:email].value} type="email" required />
            <input class="input w-full text-base" placeholder="********" name={@form[:password].name} id={@form[:password].id} value={@form[:password].value} type="password" required />

            <div class="flex items-center justify-between my-4">
              <label class="label cursor-pointer">
                <input type="hidden" name={@form[:remember_me].name} value="false" />
                <input type="checkbox" name={@form[:remember_me].name} id={@form[:remember_me].id} value="true" checked={@form[:remember_me].value} class="checkbox checkbox-sm" />
                <span class="label-text ml-2">Keep me logged in</span>
              </label>

              <.link href={~p"/reset-password"} class="text-sm font-semibold">
                Forgot your password?
              </.link>
            </div>
            <button phx-disable-with="Logging in..." class="btn btn-primary w-full">
              Log in <span aria-hidden="true">→</span>
            </button>
          </fieldset>
        </form>
      </div>
    </div>
    """
  end

  @doc """
  Initializes the LiveView with a form pre-filled with flash data.

  Sets up the initial form state, potentially pre-filling the email field
  from flash data, and configures page metadata with appropriate title
  and description.
  """
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "Log in",
        description: "Log in to your account",
        url: "/login"
      )
      |> assign(form: form)
      |> assign(csrf_token: Plug.CSRFProtection.get_csrf_token())

    {:ok, socket, temporary_assigns: [form: form]}
  end

  @doc """
  Handles form validation events.

  Updates the form state as the user types, providing real-time validation
  feedback without submitting the form.
  """
  def handle_event("validate", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form)}
  end
end
