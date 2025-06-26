defmodule Public.UserConfirmationLive do
  @moduledoc """
  LiveView for confirming user accounts via email confirmation tokens.

  This view handles the confirmation of user accounts through tokens sent via email.
  It provides a simple form with a hidden field for the token and processes the
  confirmation when submitted. After successful confirmation, users are redirected
  to the homepage with a success message.
  """
  use Public, :live_view

  alias Core.Accounts
  alias Public.PageMeta

  @doc """
  Renders the account confirmation form.

  Displays a form with a hidden token field and submission button.
  Also provides links to register or log in.
  """
  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <div class="flex items-center justify-center h-full">
      <div class="mx-auto max-w-sm">
        <.header class="text-center">Confirm Account</.header>

        <form class="form-control" id="confirmation_form" phx-submit="confirm_account">
          <fieldset class="fieldset w-full">
            <input
              type="hidden"
              name={@form[:token].name}
              id={@form[:token].id}
              value={@form[:token].value}
            />
            <button phx-disable-with="Confirming..." class="btn btn-primary mt-4 w-full">
              Confirm my account
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
  Initializes the LiveView with the token from URL parameters.

  Sets up the form with the token from the URL and configures page metadata.
  """
  def mount(%{"token" => token}, _session, socket) do
    form = to_form(%{"token" => token}, as: "user")

    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "Confirm Account",
        description: "Confirm your account to complete registration"
      )
      |> assign(form: form)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @doc """
  Handles account confirmation submission.

  Processes the token submission, attempts to confirm the user account,
  and provides appropriate feedback. Does not automatically log in the user
  after confirmation for security purposes.
  """
  def handle_event("confirm_account", %{"user" => %{"token" => token}}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User confirmed successfully.")
         |> redirect(to: ~p"/")}

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case socket.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            {:noreply, redirect(socket, to: ~p"/")}

          %{} ->
            {:noreply,
             socket
             |> put_flash(:error, "User confirmation link is invalid or it has expired.")
             |> redirect(to: ~p"/")}
        end
    end
  end
end
