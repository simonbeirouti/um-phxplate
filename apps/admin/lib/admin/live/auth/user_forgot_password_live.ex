defmodule Admin.UserForgotPasswordLive do
  @moduledoc """
  LiveView for requesting password reset instructions for admin users.

  This view allows admin users who have forgotten their password to request a password
  reset link. It provides a form for users to enter their email address and handles
  sending the reset instructions email if the account exists and is a super admin.
  """
  use Admin, :live_view

  alias Core.Accounts
  alias Admin.PageMeta

  @doc """
  Renders the password reset request form.

  Displays a form with an email field and submission button,
  along with links to the main login page.
  """
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4">
      <div class="w-full max-w-sm">
        <.header class="text-center">
          Reset Admin Password
          <:subtitle>
            We'll send a password reset link to your admin email
          </:subtitle>
        </.header>

        <form class="form-control" id="reset_password_form" phx-submit="send_email">
          <fieldset class="fieldset w-full">
            <input
              class="input w-full text-base"
              name={@form[:email].name}
              id={@form[:email].id}
              value={@form[:email].value}
              type="email"
              placeholder="admin@example.com"
              required
            />
            <button phx-disable-with="Sending..." class="btn btn-primary my-2 w-full">
              Send password reset instructions
            </button>
          </fieldset>
        </form>

        <div class="flex flex-col items-center justify-center gap-4">
          <div class="w-full h-px bg-base-300" />
          <.link class="w-full" href={~p"/"}>
            <button class="btn w-full">
              <.icon name="hero-arrow-left" class="w-4 h-4 mr-2" /> Back to Login
            </button>
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
        title: "Reset Admin Password",
        description: "Request a password reset link for admin account",
        url: "/reset-password"
      )
      |> assign(form: to_form(%{}, as: "user"))

    {:ok, socket}
  end

  @doc """
  Handles the form submission to send password reset instructions.

  Processes the email submission, looks up the user by email,
  and sends password reset instructions only if the account exists
  and has super_admin role. For security, always shows the same
  success message regardless of whether the email exists or has
  the correct role.
  """
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    case Accounts.get_user_by_email(email) do
      %{role: :super_admin} = user ->
        # Only send reset instructions to super admin users
        Accounts.deliver_user_reset_password_instructions(
          user,
          &url(~p"/reset-password/#{&1}")
        )

      _ ->
        # Don't reveal if email exists but isn't super admin
        :ok
    end

    info =
      "If your email is in our system and has admin privileges, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
