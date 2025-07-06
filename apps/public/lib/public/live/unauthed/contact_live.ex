defmodule Public.ContactLive do
  @moduledoc """
  LiveView for the contact form page.

  This view provides a contact form that allows users (both authenticated and guests)
  to send messages to the site administrators. The form includes fields for name,
  email, subject, and message content. If a user is authenticated, their email is
  pre-filled. The form submission results in an email notification being sent.
  """
  use Public, :live_view
  alias Core.Accounts.UserNotifier
  alias Public.PageMeta

  @doc """
  Renders the contact form with success message when applicable.

  Displays a form with name, email, subject, and message fields, along with
  a success message that appears briefly after successful form submission.
  """
  def render(assigns) do
    ~H"""
    <.header_section title="Contact Us" subtitle="We'd love to hear from you" />
    <div class="max-w-3xl mx-auto px-4 my-12">
      <div class="card bg-base-100 shadow-lg">
        <div class="card-body">
          <form id="contact-form" phx-submit="submit" phx-change="validate">
            <div class="space-y-6">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div class="form-control">
                  <input
                    class="input input-bordered text-base w-full"
                    name={@form[:name].name}
                    id={@form[:name].id}
                    value={@form[:name].value}
                    type="text"
                    placeholder="Your name"
                    required
                  />
                </div>
                <div class="form-control">
                  <input
                    class="input input-bordered text-base w-full"
                    name={@form[:email].name}
                    id={@form[:email].id}
                    value={@form[:email].value}
                    type="email"
                    placeholder="your@email.com"
                    required
                  />
                </div>
              </div>

              <div class="form-control">
                <input
                  class="input input-bordered text-base w-full"
                  name={@form[:subject].name}
                  id={@form[:subject].id}
                  value={@form[:subject].value}
                  placeholder="What is this regarding?"
                  required
                />
              </div>

              <div class="form-control">
                <textarea
                  class="textarea textarea-bordered text-base w-full min-h-32"
                  name={@form[:message].name}
                  id={@form[:message].id}
                  value={@form[:message].value}
                  placeholder="How can we help you?"
                  required
                ></textarea>
              </div>

              <input type="hidden" name="user_id" value={@current_user_id} />
            </div>

            <div class="card-actions justify-end mt-6">
              <button type="submit" phx-disable-with="Sending..." class="btn btn-primary w-full">
                Send Message
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    <.cta />
    """
  end

  @doc """
  Initializes the LiveView with the contact form and metadata.

  Sets up the form with empty fields (pre-filling email for authenticated users)
  and configures page metadata with appropriate title and description.
  """
  def mount(_params, _session, socket) do
    # Get current user if available
    current_user = socket.assigns[:current_user]
    current_user_email = if current_user, do: current_user.email, else: ""
    current_user_id = if current_user, do: current_user.id, else: nil

    socket =
      socket
      |> PageMeta.assign_metadata(
        title: "Contact Us",
        description: "Get in touch with our team",
        url: "/contact"
      )
      |> assign(:current_user_email, current_user_email)
      |> assign(:current_user_id, current_user_id)
      |> assign(
        :form,
        to_form(
          %{
            "name" => "",
            "email" => current_user_email,
            "subject" => "",
            "message" => ""
          },
          as: "contact"
        )
      )

    {:ok, socket}
  end

  @doc """
  Handles contact form submission.

  Processes the form data, sends an email notification via UserNotifier,
  resets the form, and displays a success flash message to the user.
  """
  def handle_event("submit", %{"contact" => contact_params, "user_id" => user_id}, socket) do
    user_id = if user_id == "", do: nil, else: user_id

    # Send email using UserNotifier
    UserNotifier.deliver_contact_form_email(
      contact_params["email"],
      contact_params["name"],
      contact_params["subject"],
      contact_params["message"],
      user_id
    )

    # Reset form and show success message
    socket =
      socket
      |> put_flash(
        :info,
        "Thank you for reaching out! We'll get back to you as soon as possible."
      )
      |> assign(
        :form,
        to_form(
          %{
            "name" => "",
            "email" => socket.assigns.current_user_email,
            "subject" => "",
            "message" => ""
          },
          as: "contact"
        )
      )

    {:noreply, socket}
  end
end
