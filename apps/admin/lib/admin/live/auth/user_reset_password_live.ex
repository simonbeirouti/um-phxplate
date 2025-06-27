defmodule Admin.UserResetPasswordLive do
  @moduledoc """
  LiveView for resetting user passwords via email tokens.

  This view allows users who have requested a password reset to set a new password.
  It validates the reset token from the URL, provides a form for entering a new
  password with confirmation, and processes the password change. It includes
  real-time validation as the user types.
  """
  use Admin, :live_view

  alias Core.Accounts

  @doc """
  Renders the password reset form.

  Displays a form with password and password confirmation fields,
  along with links to register or log in.
  """
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">Reset Password</.header>

      <form
        class="form-control"
        id="reset_password_form"
        phx-submit="reset_password"
        phx-change="validate"
      >
        <.error :if={@form.errors != []}>
          Oops, something went wrong! Please check the errors below.
        </.error>
        <fieldset class="fieldset w-full">
          <input
            class="input text-base"
            name={@form[:password].name}
            id={@form[:password].id}
            value={@form[:password].value}
            type="password"
            placeholder="********"
            required
          />
          <input
            class="input text-base"
            name={@form[:password_confirmation].name}
            id={@form[:password_confirmation].id}
            value={@form[:password_confirmation].value}
            type="password"
            placeholder="********"
            required
          />
          <button phx-disable-with="Resetting..." class="btn btn-primary mt-4 w-full">
            Reset Password
          </button>
        </fieldset>
      </form>

      <p class="text-center text-sm mt-4">
        <.link href={~p"/reset-password"}>Forgot Password?</.link> | <.link href={~p"/"}>Log in</.link>
      </p>
    </div>
    """
  end

  @doc """
  Initializes the LiveView with the token and user information.

  Validates the token from URL parameters, retrieves the associated user,
  and sets up the password change form. If the token is invalid, redirects
  with an error message.
  """
  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _ ->
          %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
