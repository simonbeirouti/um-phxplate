defmodule Admin.UserSessionController do
  @moduledoc """
  Handles user session management (login/logout) for the admin interface.
  """
  use Admin, :controller

  alias Core.Accounts
  alias Core.Auth

  @doc """
  Handles user login form submission.

  Validates the user credentials and logs them in if successful,
  otherwise redirects back to login with an error message.
  """
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      %{role: :super_admin} = user ->
        # Only super_admin users can access admin interface
        Auth.log_in_user(conn, user, user_params)

      %{role: role} when role in [:basic, :admin] ->
        # Redirect non-super_admin users to public login
        conn
        |> put_flash(:error, "Please use the main login page to access your account.")
        |> redirect(external: Core.EndpointHelper.invitation_url() <> "/login")

      nil ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/")
    end
  end

  @doc """
  Handles user logout.

  Logs out the current user and redirects to the login page.
  """
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> Auth.log_out_user()
  end
end
