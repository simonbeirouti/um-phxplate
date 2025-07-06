defmodule Core.Authorization do
  @moduledoc """
  Centralized authorization helpers for role-based access control.

  This module implements plugs and helper functions for enforcing
  role-based access control throughout the application. It supports
  three main roles: basic, admin, and super_admin with hierarchical
  access permissions.

  It also provides company ownership validation to ensure users can
  only access their own companies.
  """

  import Phoenix.Controller
  import Plug.Conn

  @doc """
  Initializes the authorization plug with the required role.

  ## Parameters

  * `role` - The role required for access, can be :basic, :admin, or :super_admin
  """
  def init(role), do: role

  @doc """
  Plug callback to check if a user has the required role.

  Verifies that the current user has the required role and redirects
  to the dashboard with an error message if not authorized.

  ## Parameters

  * `conn` - The connection struct
  * `role` - The required role (:basic, :admin, or :super_admin)
  """
  def call(conn, role) do
    if authorized?(conn.assigns.current_user, role) do
      conn
    else
      conn
      |> put_flash(:error, "You are not authorized to access this page.")
      |> redirect(to: "/dashboard")
      |> halt()
    end
  end

  @doc """
  Checks if a user has the required role.

  Returns true if the user has the required role or a higher role
  in the hierarchy (super_admin > admin > basic).

  ## Parameters

  * `user` - The user to check
  * `role` - The role to check against (:basic, :admin, or :super_admin)

  ## Examples

      iex> authorized?(user_with_admin_role, :basic)
      true

      iex> authorized?(user_with_basic_role, :admin)
      false
  """
  def authorized?(nil, _role), do: false

  def authorized?(user, role) do
    case role do
      :basic -> user.role in [:basic, :admin, :super_admin]
      :admin -> user.role in [:admin, :super_admin]
      :super_admin -> user.role == :super_admin
      _ -> false
    end
  end

  @doc """
  Plug to ensure the current user is the owner of the requested company.

  Checks if the user making the request is the owner of the company
  specified in the params. Redirects with an error message if not.

  ## Parameters

  * `conn` - The connection struct
  * `_opts` - Options (currently unused)
  """
  def ensure_company_owner(conn, _opts) do
    case conn.params do
      %{"id" => company_id} ->
        case Integer.parse(company_id) do
          {id, ""} ->
            company = Core.Companies.get_company!(id)
            if company.owner_id == conn.assigns.current_user.id do
              conn
            else
              # Determine redirect path based on app context
              redirect_path = get_company_redirect_path(conn)

              conn
              |> put_flash(:error, "You don't have access to this company")
              |> redirect(to: redirect_path)
              |> halt()
            end
          _ ->
            redirect_path = get_company_redirect_path(conn)

            conn
            |> put_flash(:error, "Invalid company ID")
            |> redirect(to: redirect_path)
            |> halt()
        end
      _ -> conn
    end
  end

  @doc """
  Checks if a user is the owner of a company.

  Returns true if the user's ID matches the company's owner ID.

  ## Parameters

  * `company` - The company to check
  * `user` - The user to check against

  ## Examples

      iex> is_company_owner?(company, company.owner)
      true

      iex> is_company_owner?(company, different_user)
      false
  """
  def is_company_owner?(company, user) do
    company.owner_id == user.id
  end

  @doc """
  Plug to ensure the current user has the required role.

  Unlike the call/2 function, this returns specific error responses
  (401 Unauthorized or 403 Forbidden) based on the authentication state.

  ## Parameters

  * `conn` - The connection struct
  * `required_role` - The role required for access
  """
  def require_role(conn, required_role) do
    case call(conn, required_role) do
      {:ok, _user} -> conn
      {:error, :unauthorized} ->
        error_view = get_error_view(conn)

        conn
        |> put_status(:unauthorized)
        |> put_view(error_view)
        |> render(:"401")
        |> halt()
      {:error, :forbidden} ->
        error_view = get_error_view(conn)

        conn
        |> put_status(:forbidden)
        |> put_view(error_view)
        |> render(:"403")
        |> halt()
    end
  end

  # Private helper functions

  defp get_company_redirect_path(conn) do
    case Core.Auth.get_app_config(conn) do
      {:ok, :admin, _config} -> "/dashboard/admin/companies"
      {:ok, :public, _config} -> "/dashboard/admin/companies"
      _ -> "/dashboard"
    end
  end

  defp get_error_view(conn) do
    case Core.Auth.get_app_config(conn) do
      {:ok, :admin, _config} -> Admin.ErrorHTML
      {:ok, :public, _config} -> Public.ErrorHTML
      _ -> Public.ErrorHTML  # Default fallback
    end
  end
end
