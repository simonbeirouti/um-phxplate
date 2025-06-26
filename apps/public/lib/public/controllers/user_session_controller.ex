defmodule Public.UserSessionController do
  use Public, :controller

  alias Core.Accounts
  alias Public.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/dashboard/account")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params} = params, info) do
    %{"email" => email, "password" => password} = user_params

    # Check if plan_id was passed from URL parameters or session
    plan_id_from_params = params["plan_id"]
    plan_id_from_session = get_session(conn, :selected_plan_id)
    selected_plan_id = plan_id_from_params || plan_id_from_session

    if user = Accounts.get_user_by_email_and_password(email, password) do
      # Track login activity
      Core.Tracking.track_user_activity("login", user, user, %{}, %{
        "ip" => conn.remote_ip |> :inet.ntoa() |> to_string(),
        "user_agent" => get_req_header(conn, "user-agent") |> List.first()
      })

      # Always preserve plan_id in session if it exists
      conn =
        if selected_plan_id do
          # If we have a selected plan, preserve it for the onboarding flow
          put_session(conn, :selected_plan_id, selected_plan_id)
        else
          conn
        end

      # For users needing onboarding, we need to check if they need to be redirected
      # with plan_id as a query parameter
      if !Core.Accounts.onboarding_completed?(user) do
        if selected_plan_id do
          # Explicitly set the return path with plan_id if user needs onboarding
          ^conn = put_session(conn, :user_return_to, ~p"/onboarding?plan_id=#{selected_plan_id}")
        end
      end

      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    # Track logout activity
    if user = conn.assigns.current_user do
      Core.Tracking.track_user_activity("logout", user, user, %{}, %{
        "ip" => conn.remote_ip |> :inet.ntoa() |> to_string(),
        "user_agent" => get_req_header(conn, "user-agent") |> List.first()
      })
    end

    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
