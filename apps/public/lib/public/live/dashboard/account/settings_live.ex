defmodule Public.Dashboard.Account.SettingsLive do
  @moduledoc """
  LiveComponent for managing user account settings.

  This component provides forms for users to update their email address
  and password, with appropriate validation and error handling.
  """
  use Public, :live_component
  alias Core.Accounts

  @doc """
  Updates the component with initial form state.

  Initializes forms for email and password changes with empty values.
  """
  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:email_form, to_form(%{}, as: :user))
      |> assign(:email_form_current_password, nil)
      |> assign(:password_form, to_form(%{}, as: :user))
      |> assign(:password_form_current_password, nil)
      |> assign(:loading_email, false)
      |> assign(:loading_password, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    email_form = to_form(user_params, as: :user)

    socket =
      socket
      |> assign(:email_form, email_form)
      |> assign(:email_form_current_password, password)

    {:noreply, socket}
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    password_form = to_form(user_params, as: :user)

    socket =
      socket
      |> assign(:password_form, password_form)
      |> assign(:password_form_current_password, password)

    {:noreply, socket}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.user

    socket = assign(socket, :loading_email, true)

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/dashboard/account/confirm_email/#{&1}")
        )

        send(
          self(),
          {:flash_msg, :info,
           "A link to confirm your email change has been sent to the new address."}
        )

        {:noreply,
         socket
         |> assign(:loading_email, false)
         |> assign(:email_form, to_form(%{}, as: :user))
         |> assign(:email_form_current_password, nil)}

      {:error, changeset} ->
        message =
          cond do
            changeset.errors[:current_password] ->
              "Failed to update email. The current password is not valid."

            changeset.errors[:email] ->
              case changeset.errors[:email] do
                {"did not change", _} ->
                  "The new email must be different from your current email."

                {msg, _} ->
                  "Failed to update email: #{msg}"
              end

            true ->
              "Failed to update email. Please check your inputs and try again."
          end

        send(self(), {:flash_msg, :error, message})

        {:noreply,
         socket
         |> assign(:loading_email, false)
         |> assign(:email_form, to_form(Map.put(user_params, "action", :validate), as: :user))}
    end
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.user

    socket = assign(socket, :loading_password, true)

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:loading_password, false)
         |> assign(:password_form, to_form(%{}, as: :user))
         |> assign(:password_form_current_password, nil)
         |> assign(:user, user)
         |> put_flash(:info, "Password updated successfully. You will be signed out.")
         |> push_navigate(to: ~p"/login")}

      {:error, changeset} ->
        message =
          if changeset.errors[:current_password] do
            "Failed to update password. The current password is not valid."
          else
            "Failed to update password. Please check the errors below."
          end

        send(self(), {:flash_msg, :error, message})

        {:noreply,
         socket
         |> assign(:loading_password, false)
         |> assign(:password_form, to_form(Map.put(changeset, :action, :validate), as: :user))
         |> assign(:password_form_current_password, password)}
    end
  end

  @doc """
  Renders the settings forms.

  Displays forms for changing email and password with appropriate
  validation and loading states.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Change Email Card -->
      <div class="card bg-base-100 shadow-lg">
        <div class="card-body">
          <h2 class="card-title text-xl mb-2">Change Email</h2>
          <p class="text-base-content/70 mb-6">Change your account email address</p>

          <form
            id="email_form"
            phx-target={@myself}
            phx-submit="update_email"
            phx-change="validate_email"
            class="space-y-4"
          >
            <div class="form-control w-full">
              <label class="label">
                <span class="label-text">Email</span>
              </label>
              <input
                name="user[email]"
                type="email"
                placeholder="your@email.com"
                class="input input-bordered w-full"
                value={@email_form[:email].value}
                required
              />
              <%= if @email_form[:email].errors != [] do %>
                <label class="label">
                  <span class="label-text-alt text-error">
                    {Enum.map(@email_form[:email].errors, &elem(&1, 0)) |> Enum.join(", ")}
                  </span>
                </label>
              <% end %>
            </div>

            <div class="form-control w-full">
              <label class="label">
                <span class="label-text">Current Password</span>
              </label>
              <input
                name="current_password"
                id="current_password_for_email"
                type="password"
                placeholder="********"
                class="input input-bordered w-full"
                value={@email_form_current_password}
                required
              />
            </div>

            <button
              type="submit"
              phx-disable-with="Changing..."
              disabled={@loading_email}
              class="btn btn-primary w-full"
            >
              <%= if @loading_email do %>
                <span class="loading loading-spinner loading-sm"></span> Changing...
              <% else %>
                Change Email
              <% end %>
            </button>
          </form>
        </div>
      </div>

    <!-- Change Password Card -->
      <div class="card bg-base-100 shadow-lg">
        <div class="card-body">
          <h2 class="card-title text-xl mb-2">Change Password</h2>
          <p class="text-base-content/70 mb-6">Change your account password</p>

          <form
            id="password_form"
            phx-target={@myself}
            phx-submit="update_password"
            phx-change="validate_password"
            class="space-y-4"
          >
            <div class="form-control w-full">
              <label class="label">
                <span class="label-text">Current Password</span>
              </label>
              <input
                name="current_password"
                type="password"
                placeholder="********"
                class="input input-bordered w-full"
                value={@password_form_current_password}
                required
              />
            </div>

            <div class="form-control w-full">
              <label class="label">
                <span class="label-text">New Password</span>
              </label>
              <input
                name="user[password]"
                type="password"
                placeholder="********"
                class="input input-bordered w-full"
                value={@password_form[:password].value}
                required
              />
              <%= if @password_form[:password].errors != [] do %>
                <label class="label">
                  <span class="label-text-alt text-error">
                    {Enum.map(@password_form[:password].errors, &elem(&1, 0)) |> Enum.join(", ")}
                  </span>
                </label>
              <% end %>
            </div>

            <div class="form-control w-full">
              <label class="label">
                <span class="label-text">Confirm New Password</span>
              </label>
              <input
                name="user[password_confirmation]"
                type="password"
                placeholder="********"
                class="input input-bordered w-full"
                value={@password_form[:password_confirmation].value}
                required
              />
              <%= if @password_form[:password_confirmation].errors != [] do %>
                <label class="label">
                  <span class="label-text-alt text-error">
                    {Enum.map(@password_form[:password_confirmation].errors, &elem(&1, 0))
                    |> Enum.join(", ")}
                  </span>
                </label>
              <% end %>
            </div>

            <button
              type="submit"
              phx-disable-with="Changing..."
              disabled={@loading_password}
              class="btn btn-primary w-full"
            >
              <%= if @loading_password do %>
                <span class="loading loading-spinner loading-sm"></span> Changing...
              <% else %>
                Change Password
              <% end %>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
