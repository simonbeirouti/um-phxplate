defmodule Public.UserConfirmationInstructionsLive do
  @moduledoc """
  LiveView for requesting new account confirmation instructions.

  This view allows users who haven't received or have lost their confirmation email
  to request a new confirmation link. It provides a form for users to enter their
  email address and handles sending a new confirmation email if the account exists.
  """
  use Public, :live_view

  alias Core.Accounts

  @doc """
  Renders the form for requesting confirmation instructions.

  Displays a form with an email field and submission button,
  along with links to register or log in.
  """
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-full">
      <div class="mx-auto max-w-sm">
        <.header class="text-center">
          No confirmation instructions received?
          <:subtitle>We'll send a new confirmation link to your inbox</:subtitle>
        </.header>

        <form class="form-control" id="resend_confirmation_form" phx-submit="send_instructions">
          <fieldset class="fieldset w-full">
            <input
              class="input text-base"
              name={@form[:email].name}
              id={@form[:email].id}
              value={@form[:email].value}
              type="email"
              placeholder="your@email.com"
              required
            />
            <button phx-disable-with="Sending..." class="btn btn-primary mt-4 w-full">
              Resend confirmation instructions
            </button>
          </fieldset>
        </form>

        <p class="text-center mt-4">
          <.link href={~p"/register"}>Register</.link> | <.link href={~p"/login"}>Log in</.link>
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Initializes the LiveView with an empty form.

  Sets up the initial form state for the email input field.
  """
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  @doc """
  Handles the form submission to send confirmation instructions.

  Processes the email submission, looks up the user by email,
  and sends new confirmation instructions if the account exists.
  For security, always shows the same success message regardless of
  whether the email exists in the system.
  """
  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/confirm/#{&1}")
      )
    end

    info =
      "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
