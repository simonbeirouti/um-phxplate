defmodule Public.Dashboard.Admin.CompanyHelpers do
  @moduledoc """
  Helper functions for company management across live views.

  This module provides reusable functions for common company-related operations
  that are used by multiple live views in the admin dashboard, such as creating
  companies and handling company dialog events.
  """
  alias Core.{Companies, Repo}
  import Phoenix.Component
  import Phoenix.LiveView

  @doc """
  Handles company creation from form submission.

  Creates a new company with the provided parameters and associates it with
  the current user. Updates the socket with the new company and displays
  appropriate success or error messages.

  ## Parameters

  * `socket` - The LiveView socket
  * `params` - Company form parameters

  ## Returns

  * `{:noreply, updated_socket}` - The updated socket with the new company
  """
  def handle_create_company(socket, params) do
    current_user = Repo.preload(socket.assigns.current_user, :profile)

    company_params = %{
      name: params["name"],
      phone: params["phone"],
      website: params["website"],
      email: params["email"],
      address: params["address"],
      description: params["description"],
      owner_id: current_user.id
    }

    case Companies.create_company(company_params, current_user) do
      {:ok, company} ->
        {:noreply,
         socket
         |> update(:companies, fn companies -> [company | companies] end)
         |> put_flash(:info, "Company created successfully!")
         |> push_event("hide-modal", %{id: "create-company-dialog"})}

      {:error, :limit_reached} ->
        {:noreply,
         socket
         |> put_flash(:error, "You have reached the maximum number of companies for your plan.")}

      {:error, changeset} ->
        error_message =
          case changeset.errors do
            [{field, {msg, _}} | _] -> "#{Phoenix.Naming.humanize(field)} #{msg}"
            _ -> "Failed to create company. Please try again."
          end

        {:noreply,
         socket
         |> put_flash(:error, error_message)}
    end
  end

  @doc """
  Handles opening the create company dialog.

  This is a placeholder function that can be extended to prepare
  any necessary data before showing the dialog.

  ## Parameters

  * `socket` - The LiveView socket

  ## Returns

  * `{:noreply, socket}` - The unchanged socket
  """
  def handle_open_create_company_dialog(socket) do
    {:noreply, socket}
  end
end
