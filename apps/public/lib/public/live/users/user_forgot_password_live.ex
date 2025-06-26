defmodule Public.UserForgotPasswordLive do
  @moduledoc """
  LiveView for requesting password reset instructions.

  This view allows users who have forgotten their password to request a password
  reset link. It provides a form for users to enter their email address and handles
  sending the reset instructions email if the account exists in the system.
  """
  use Public, :live_view

  alias Core.Accounts
  alias Public.PageMeta

  @doc """
  Renders the password reset request form.

  Displays a form with an email field and submission button,
  along with links to register or log in.
  """
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-full">
      <div class="w-full max-w-sm mt-64 lg:mt-0">
        <.header class="text-center">
          Forgot your password?
          <:subtitle>We'll send a password reset link to your inbox</:subtitle>
        </.header>

        <form class="form-control" id="reset_password_form" phx-submit="send_email">
          <fieldset class="fieldset w-full">
            <input class="input text-base" name={@form[:email].name} id={@form[:email].id} value={@form[:email].value} type="email" placeholder="your@email.com" required />
            <button phx-disable-with="Sending..." class="btn btn-primary mt-4 w-full">
              Send password reset instructions
            </button>
          </fieldset>
        </form>
        <div class="flex flex-col items-center justify-center gap-4 mt-4">
          <div class="w-full h-px bg-primary/50" />
          <.link class="w-full" href={~p"/register"}>
            <button class="btn w-full">Register</button>
          </.link>
          <.link class="w-full" href={~p"/login"}>
            <button class="btn w-full">Log in</button>
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Initializes the LiveView with an empty form and page metadata.

  Sets up the initial form state for the email input field and
  configures page metadata with appropriate title and description.
  """
  def mount(_params, _session, socket) do
    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "Reset Password",
        description: "Request a password reset link",
        url: "/reset-password"
      )
      |> assign(form: to_form(%{}, as: "user"))

    {:ok, socket}
  end

  @doc """
  Handles the form submission to send password reset instructions.

  Processes the email submission, looks up the user by email,
  and sends password reset instructions if the account exists.
  For security, always shows the same success message regardless of
  whether the email exists in the system.
  """
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/reset-password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
