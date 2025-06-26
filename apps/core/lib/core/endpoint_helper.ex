defmodule Core.EndpointHelper do
  @moduledoc """
  Helper module for determining which endpoint to use in different contexts.

  Since this is an umbrella app with multiple web endpoints (Public and Admin),
  this module provides functions to get the appropriate endpoint based on context.
  """

  @doc """
  Returns the public endpoint module.
  """
  def public_endpoint do
    if Code.ensure_loaded?(Public.Endpoint) do
      Public.Endpoint
    else
      nil
    end
  end

  @doc """
  Returns the admin endpoint module.
  """
  def admin_endpoint do
    if Code.ensure_loaded?(Admin.Endpoint) do
      Admin.Endpoint
    else
      nil
    end
  end

  @doc """
  Returns the appropriate endpoint for company invitations.
  Company invitations are typically handled by the public app.
  """
  def invitation_endpoint, do: public_endpoint()

  @doc """
  Returns the appropriate endpoint for admin notifications.
  Admin notifications should use the admin endpoint.
  """
  def admin_notification_endpoint, do: admin_endpoint()

  @doc """
  Gets the URL for company invitations.
  Uses the configured public_base_url in production, otherwise uses the public endpoint URL.
  """
  def invitation_url do
    case Application.get_env(:core, :env, Mix.env()) do
      :prod ->
        Core.config([:public_base_url])
      _ ->
        if endpoint = invitation_endpoint() do
          endpoint.url()
        else
          Core.config([:public_base_url])
        end
    end
  end

  @doc """
  Gets the URL for admin features.
  Uses the configured admin_base_url in production, otherwise uses the admin endpoint URL.
  """
  def admin_url do
    case Application.get_env(:core, :env, Mix.env()) do
      :prod ->
        Core.config([:admin_base_url])
      _ ->
        if endpoint = admin_endpoint() do
          endpoint.url()
        else
          Core.config([:admin_base_url])
        end
    end
  end

  @doc """
  Signs a Phoenix token using the appropriate endpoint.

  ## Parameters
    - context: :invitation | :admin | atom - determines which endpoint to use
    - salt: The salt for the token
    - data: The data to sign
  """
  def sign_token(context, salt, data) do
    endpoint = get_endpoint_for_context(context)
    if endpoint && Code.ensure_loaded?(Phoenix.Token) do
      Phoenix.Token.sign(endpoint, salt, data)
    else
      {:error, :endpoint_not_available}
    end
  end

  @doc """
  Verifies a Phoenix token using the appropriate endpoint.

  ## Parameters
    - context: :invitation | :admin | atom - determines which endpoint to use
    - salt: The salt for the token
    - token: The token to verify
    - opts: Options for verification (e.g., max_age)
  """
  def verify_token(context, salt, token, opts \\ []) do
    endpoint = get_endpoint_for_context(context)
    if endpoint && Code.ensure_loaded?(Phoenix.Token) do
      Phoenix.Token.verify(endpoint, salt, token, opts)
    else
      {:error, :endpoint_not_available}
    end
  end

  # Private function to determine endpoint based on context
  defp get_endpoint_for_context(:invitation), do: public_endpoint()
  defp get_endpoint_for_context(:admin), do: admin_endpoint()
  defp get_endpoint_for_context(_), do: public_endpoint() # default to public
end
