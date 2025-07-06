defmodule Core.Auth do
  @moduledoc """
  Centralized authentication and authorization functionality.

  This module provides unified authentication logic for both Admin and Public apps,
  with app-specific configuration and role-based access control:

  - Super admins can only access the Admin app
  - Basic and admin users can only access the Public app
  - Handles app-specific cookies, endpoints, and redirect logic
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Core.Accounts

  # App-specific configuration
  @app_configs %{
    admin: %{
      cookie_name: "_phxplate_admin_web_user_remember_me",
      endpoint: Admin.Endpoint,
      login_path: "/login",
      dashboard_path: "/dashboard",
      allowed_roles: [:super_admin]
    },
    public: %{
      cookie_name: "_phxplate_public_web_user_remember_me",
      endpoint: Public.Endpoint,
      login_path: "/login",
      dashboard_path: "/",
      allowed_roles: [:basic, :admin]
    }
  }

  # Make the remember me cookie valid for 60 days
  @max_age 60 * 60 * 24 * 60
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Gets the app configuration based on the endpoint module.
  """
  def get_app_config(endpoint_module) when is_atom(endpoint_module) do
    case endpoint_module do
      Admin.Endpoint -> {:ok, :admin, @app_configs.admin}
      Public.Endpoint -> {:ok, :public, @app_configs.public}
      _ -> {:error, :unknown_app}
    end
  end

  def get_app_config(conn) when is_struct(conn, Plug.Conn) do
    # Determine app from the endpoint
    case conn.private[:phoenix_endpoint] do
      Admin.Endpoint ->
        {:ok, :admin, @app_configs.admin}

      _ ->
        {:ok, :public, @app_configs.public}
    end
  end

  @doc """
  Logs the user in with app-specific configuration.
  """
  def log_in_user(conn, user, params \\ %{}) do
    with {:ok, app_type, config} <- get_app_config(conn) do
      # Check if user is allowed to access this app
      unless user.role in config.allowed_roles do
        conn
        |> put_flash(:error, "You don't have permission to access this application.")
        |> redirect(to: get_redirect_path_for_user(user))
        |> halt()
      else
        token = Accounts.generate_user_session_token(user)
        user_return_to = get_session(conn, :user_return_to)

        conn
        |> renew_session(app_type)
        |> put_token_in_session(token)
        |> delete_session(:impersonated_user_id)
        |> maybe_write_remember_me_cookie(token, params, config.cookie_name)
        |> redirect(to: user_return_to || signed_in_path(conn, user, config))
      end
    else
      {:error, :unknown_app} ->
        conn
        |> put_flash(:error, "Unable to determine application context.")
        |> redirect(to: "/")
        |> halt()
    end
  end

  @doc """
  Logs the user out with app-specific configuration.
  """
  def log_out_user(conn) do
    with {:ok, app_type, config} <- get_app_config(conn) do
      if live_socket_id = get_session(conn, :live_socket_id) do
        config.endpoint.broadcast(live_socket_id, "disconnect", %{})
      end

      conn
      |> renew_session(app_type)
      |> delete_resp_cookie(config.cookie_name)
      |> delete_session(:impersonated_user_id)
      |> redirect(to: config.login_path)
    else
      {:error, :unknown_app} ->
        conn
        |> redirect(to: "/")
    end
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    with {:ok, _app_type, config} <- get_app_config(conn) do
      {user_token, conn} = ensure_user_token(conn, config.cookie_name)
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
    else
      {:error, :unknown_app} ->
        assign(conn, :current_user, nil)
    end
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      with {:ok, _app_type, config} <- get_app_config(conn) do
        conn
        |> redirect(to: signed_in_path(conn, conn.assigns.current_user, config))
        |> halt()
      else
        {:error, :unknown_app} ->
          conn
          |> redirect(to: "/")
          |> halt()
      end
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      with {:ok, app_type, config} <- get_app_config(conn) do
        user = conn.assigns.current_user

        # Check if user is allowed to access this app
        unless user.role in config.allowed_roles do
          conn
          |> put_flash(:error, "You don't have permission to access this application.")
          |> redirect(to: get_redirect_path_for_user(user))
          |> halt()
        else
          # Public app specific: check onboarding completion
          if app_type == :public &&
             !Accounts.onboarding_completed?(user) &&
             !String.starts_with?(conn.request_path, "/onboarding") do
            # Pass selected_plan_id to onboarding if available
            plan_id_from_params = conn.params["plan_id"]
            plan_id_from_session = get_session(conn, :selected_plan_id)
            selected_plan_id = plan_id_from_params || plan_id_from_session

            if selected_plan_id do
              conn
              |> redirect(to: "/onboarding?plan_id=#{selected_plan_id}")
              |> halt()
            else
              conn
              |> redirect(to: "/onboarding")
              |> halt()
            end
          else
            conn
          end
        end
      else
        {:error, :unknown_app} ->
          conn
          |> put_flash(:error, "Unable to determine application context.")
          |> redirect(to: "/")
          |> halt()
      end
    else
      with {:ok, _app_type, config} <- get_app_config(conn) do
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> maybe_store_return_to()
        |> redirect(to: config.login_path)
        |> halt()
      else
        {:error, :unknown_app} ->
          conn
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: "/")
          |> halt()
      end
    end
  end

  # LiveView mount callbacks

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.
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
      user = socket.assigns.current_user

      # Determine app context from socket
      app_type = determine_app_from_socket(socket)
      config = @app_configs[app_type]

      # Check if user is allowed to access this app
      unless user.role in config.allowed_roles do
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You don't have permission to access this application.")
         |> Phoenix.LiveView.redirect(to: get_redirect_path_for_user(user))}
      else
        # Public app specific: check onboarding completion
        if app_type == :public &&
           !Accounts.onboarding_completed?(user) &&
           !onboarding_path?(socket) do
          # Get plan_id from params first, or fall back to session
          plan_id_from_params = params["plan_id"]
          plan_id_from_session = session["selected_plan_id"]
          selected_plan_id = plan_id_from_params || plan_id_from_session

          query_params = if selected_plan_id, do: %{plan_id: selected_plan_id}, else: %{}

          {:halt, Phoenix.LiveView.redirect(socket, to: "/onboarding?#{URI.encode_query(query_params)}")}
        else
          # Pass selected_plan_id to socket if available (for public app)
          socket = if app_type == :public do
            plan_id_from_params = params["plan_id"]
            plan_id_from_session = session["selected_plan_id"]
            selected_plan_id = plan_id_from_params || plan_id_from_session

            if selected_plan_id do
              Phoenix.Component.assign(socket, :selected_plan_id, selected_plan_id)
            else
              socket
            end
          else
            socket
          end

          {:cont, socket}
        end
      end
    else
      app_type = determine_app_from_socket(socket)
      config = @app_configs[app_type]

      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
       |> Phoenix.LiveView.redirect(to: config.login_path)}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      app_type = determine_app_from_socket(socket)
      config = @app_configs[app_type]

      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path_lv(socket.assigns.current_user, config))}
    else
      {:cont, socket}
    end
  end

  # Private functions

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, cookie_name) do
    put_resp_cookie(conn, cookie_name, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params, _cookie_name) do
    conn
  end

  defp renew_session(conn, app_type) do
    delete_csrf_token()

    # Only preserve selected plan ID if user is coming from pricing page (public app only)
    selected_plan_id = if app_type == :public && is_pricing_referer?(conn) do
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

  # Check if referer indicates user is coming from pricing page (public app only)
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

  defp ensure_user_token(conn, cookie_name) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [cookie_name])

      if token = conn.cookies[cookie_name] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
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

  defp signed_in_path(conn, user, config) do
    case config do
      %{allowed_roles: [:super_admin]} ->
        # Admin app
        config.dashboard_path
      _ ->
        # Public app
        if conn.assigns[:current_user] && !Accounts.onboarding_completed?(user) do
          "/onboarding"
        else
          config.dashboard_path
        end
    end
  end

  defp signed_in_path_lv(user, config) do
    case config do
      %{allowed_roles: [:super_admin]} ->
        # Admin app
        config.dashboard_path
      _ ->
        # Public app
        if !Accounts.onboarding_completed?(user) do
          "/onboarding"
        else
          config.dashboard_path
        end
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

  defp determine_app_from_socket(socket) do
    # Try to determine app from socket context
    cond do
      socket.endpoint == Admin.Endpoint -> :admin
      socket.endpoint == Public.Endpoint -> :public
      # Fallback: check view module
      socket.view && String.starts_with?(to_string(socket.view), "Admin") -> :admin
      true -> :public
    end
  end

  defp get_redirect_path_for_user(user) do
    case user.role do
      :super_admin ->
        # Super admin should go to admin app's dashboard
        @app_configs.admin.dashboard_path

      _ ->
        # Basic/admin users should go to public app's dashboard
        @app_configs.public.dashboard_path
    end
  end
end
