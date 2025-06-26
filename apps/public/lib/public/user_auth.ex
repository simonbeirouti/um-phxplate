defmodule Public.UserAuth do
  @moduledoc """
  Handles user authentication and impersonation functionality.
  Impersonation is only available to super admin users.
  """
  use Public, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Core.Accounts

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_phxplate_public_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> delete_session(:impersonated_user_id)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    delete_csrf_token()

    # Only preserve selected plan ID if user is coming from pricing page
    selected_plan_id = if is_pricing_referer?(conn) do
      get_session(conn, :selected_plan_id)
    else
      nil
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> maybe_put_selected_plan_id(selected_plan_id)
  end

  defp maybe_put_selected_plan_id(conn, nil), do: conn
  defp maybe_put_selected_plan_id(conn, plan_id), do: put_session(conn, :selected_plan_id, plan_id)

  # Check if referer indicates user is coming from pricing page or registration flow
  defp is_pricing_referer?(conn) do
    referer = case Plug.Conn.get_req_header(conn, "referer") do
      [ref | _] -> ref
      _ -> nil
    end
    current_path = conn.request_path

    # Check for plan_id parameter in the login form submission
    plan_id_in_params = conn.params["plan_id"] != nil

    cond do
      # Direct path check - user is on pricing page
      current_path == "/pricing" -> true
      # Check if the referer URL contains the pricing path
      is_binary(referer) && String.contains?(referer, "/pricing") -> true
      # Check if coming from registration with plan_id
      is_binary(referer) && String.contains?(referer, "/register") && plan_id_in_params -> true
      # Check if this is login with plan_id in params (from registration)
      current_path == "/login" && plan_id_in_params -> true
      # Check for _action=registered with plan_id in params (completing registration flow)
      conn.params["_action"] == "registered" && plan_id_in_params -> true
      # Otherwise not from pricing
      true -> false
    end
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      Public.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    # Clear impersonation on logout
    |> delete_session(:impersonated_user_id)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    impersonated_user_id = get_session(conn, :impersonated_user_id)

    cond do
      # If there's an impersonated user and the real user is a super admin
      impersonated_user_id && user && user.role == :super_admin ->
        impersonated_user = Accounts.get_user!(impersonated_user_id)

        conn
        |> assign(:current_user, impersonated_user)
        |> assign(:real_user, user)

      # Normal case - no impersonation
      true ->
        assign(conn, :current_user, user)
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule PhxplateWeb.PageLive do
        use PhxplateWeb, :live_view

        on_mount {PhxplateWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{PhxplateWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    socket = mount_current_user(socket, session)

    # Add real_user to socket assigns if present
    real_user =
      if user_token = session["user_token"] do
        real_user = Accounts.get_user_by_session_token(user_token)

        if real_user && real_user.role == :super_admin && session["impersonated_user_id"] do
          real_user
        end
      end

    {:cont, Phoenix.Component.assign(socket, :real_user, real_user)}
  end

  def on_mount(:ensure_proper_role, _params, _session, socket) do
    user = socket.assigns.current_user
    real_user = socket.assigns[:real_user]
    request_path = socket.assigns[:current_path] || "/"

    cond do
      # Block access to super admin routes when impersonating
      String.contains?(request_path, "/super_admin") && real_user != nil ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           "Cannot access super admin pages while impersonating"
         )
         |> Phoenix.LiveView.redirect(to: "/dashboard")}

      # Block access to admin routes for non-admin users
      String.contains?(request_path, "/admin") &&
          !(user.role in [:admin, :super_admin]) ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You don't have permission to access this page")
         |> Phoenix.LiveView.redirect(to: "/dashboard")}

      true ->
        {:cont, socket}
    end
  end

  def on_mount(:ensure_authenticated, params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      # Check if user has completed onboarding
      if !Accounts.onboarding_completed?(socket.assigns.current_user) &&
           !onboarding_path?(socket) do
        # Get plan_id from params first, or fall back to session if not available
        # This ensures we prioritize plan_id directly in the URL
        plan_id_from_params = params["plan_id"]
        plan_id_from_session = session["selected_plan_id"]
        selected_plan_id = plan_id_from_params || plan_id_from_session

        # Always include plan_id if present - we don't need to check source path
        # for onboarding redirects since this is the intended flow
        query_params = if selected_plan_id, do: %{plan_id: selected_plan_id}, else: %{}

        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/onboarding?#{query_params}")}
      else
        # Get plan_id from params first, or fall back to session if not available
        # This ensures we prioritize plan_id directly in the URL
        plan_id_from_params = params["plan_id"]
        plan_id_from_session = session["selected_plan_id"]
        selected_plan_id = plan_id_from_params || plan_id_from_session

        # Always pass the selected_plan_id to the socket if it exists
        socket = if selected_plan_id do
          Phoenix.Component.assign(socket, :selected_plan_id, selected_plan_id)
        else
          socket
        end

        {:cont, socket}
      end
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket.assigns.current_user))}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  defp onboarding_path?(socket) do
    # Check if the current view is part of the onboarding flow
    socket.view in [Public.Onboarding.ProfileLive, Public.Onboarding.CompleteLive]
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      # Check if user has completed onboarding
      if !Accounts.onboarding_completed?(conn.assigns.current_user) &&
           !String.starts_with?(conn.request_path, "/onboarding") do
        # Pass selected_plan_id to onboarding if available from session or params
        plan_id_from_params = conn.params["plan_id"]
        plan_id_from_session = get_session(conn, :selected_plan_id)
        selected_plan_id = plan_id_from_params || plan_id_from_session

        if selected_plan_id do
          conn
          |> redirect(to: ~p"/onboarding?plan_id=#{selected_plan_id}")
          |> halt()
        else
          conn
          |> redirect(to: ~p"/onboarding")
          |> halt()
        end
      else
        conn
      end
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(%Plug.Conn{} = conn) do
    if conn.assigns[:current_user] && !Accounts.onboarding_completed?(conn.assigns.current_user) do
      ~p"/onboarding"
    else
      ~p"/"  # Redirect to home page since dashboard is not implemented yet
    end
  end

  defp signed_in_path(user) when is_struct(user, Core.Accounts.User) do
    if !Accounts.onboarding_completed?(user) do
      ~p"/onboarding"
    else
      ~p"/"  # Redirect to home page since dashboard is not implemented yet
    end
  end

  defp signed_in_path(_), do: ~p"/"
end
