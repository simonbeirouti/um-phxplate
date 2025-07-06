defmodule Core.Accounts.UserNotifier do
  import Swoosh.Email
  require Logger

  alias Core.Mailer
  alias Core.EndpointHelper

  # Helper functions to get app configuration
  defp app_name, do: Application.get_env(:public, :title, "PHXPlate")
  defp app_email, do: Application.get_env(:public, :email, "no-reply@cmpnd.cc")
  defp support_email, do: Application.get_env(:public, :support_email, "hello@simonbeirouti.com")

  # Common email CSS styles
  defp email_styles do
    """
    /* Base styles for all email clients */
    body {
      font-family: sans-serif;
      line-height: 1.6;
      color: #0a0b0e; /* --foreground: 224 71.4% 4.1% */
      background-color: #f8f9fc; /* --secondary: 220 14.3% 95.9% */
      margin: 0;
      padding: 0;
    }
    .container {
      width: 100%;
      max-width: 600px;
      margin: 0 auto;
      background-color: #ffffff; /* --background: 0 0% 100% */
      border-radius: 1rem; /* --radius: 1rem */
      border: 1px solid #e6e8ec; /* --border: 220 13% 91% */
    }
    .header {
      text-align: center;
      padding: 20px 0;
      border-bottom: 1px solid #e6e8ec; /* --border: 220 13% 91% */
    }
    .content {
      padding: 20px;
    }
    .footer {
      text-align: center;
      color: #717789; /* --muted-foreground: 220 8.9% 46.1% */
      font-size: 14px;
      padding: 20px 0;
      border-top: 1px solid #e6e8ec; /* --border: 220 13% 91% */
    }
    .button {
      display: inline-block;
      padding: 10px 20px;
      margin: 20px 0;
      background-color: #141c2e; /* --primary: 220.9 39.3% 11% */
      color: #f5f7fe !important; /* --primary-foreground: 210 20% 98% */
      text-decoration: none;
      border-radius: 0.5rem;
      font-weight: bold;
    }
    .message-box {
      padding: 15px;
    }
    h1, h2, h3 {
      color: #0a0b0e; /* --foreground: 224 71.4% 4.1% */
    }
    a {
      color: #141c2e; /* --primary: 220.9 39.3% 11% */
      text-decoration: underline;
    }
    """
  end

  # Email layout template with content injection
  defp email_layout(title, content, app_name, year, recipient_email) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width">
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
      <title>#{title}</title>
      <style>
        #{email_styles()}
      </style>
    </head>
    <body>
      <table width="100%" border="0" cellspacing="0" cellpadding="0">
        <tr>
          <td align="center" style="padding: 20px 0;">
            <div class="container">
              <div class="header">
                <h2>#{app_name}</h2>
              </div>
              <div class="content">
                #{content}
              </div>
              <div class="footer">
                <p>&copy; #{year} #{app_name}</p>
                <p><small>This email was sent to #{recipient_email}</small></p>
              </div>
            </div>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  # Helper function to render an email template with assigns
  defp render_email_template(template_assigns) do
    assigns = template_assigns
    app_name = assigns[:app_name]
    year = assigns[:year]

    content = case assigns[:template] do
      "chat_transcript" ->
        """
        <h2>Hi #{assigns.recipient_name},</h2>
        <p>Thank you for chatting with us. Below is a transcript of your conversation:</p>

        <div class="message-box">
          <p><strong>Session ID:</strong> #{assigns.session_id}</p>
          <p><strong>Started:</strong> #{Calendar.strftime(assigns.started_at, "%B %d, %Y at %I:%M %p")}</p>
          #{if assigns.ended_at, do: "<p><strong>Ended:</strong> #{Calendar.strftime(assigns.ended_at, "%B %d, %Y at %I:%M %p")}</p>", else: ""}
        </div>

        <div class="message-box" style="max-height: 400px; overflow-y: auto;">
          <style>
            .message-line { margin-bottom: 8px; }
            .timestamp { color: #717789; font-size: 12px; }
            .transcript-header { font-weight: bold; margin-bottom: 10px; }
          </style>
          #{assigns.transcript}
        </div>

        <p>If you have any further questions, please don't hesitate to contact us.</p>
        """

      "confirmation_instructions" ->
        """
        <h2>Hi #{assigns.user.email},</h2>
        <p>You can confirm your account by clicking the button below:</p>
        <div style="text-align: center;">
          <a href="#{assigns.url}" class="button">Confirm Account</a>
        </div>
        <p>If you're having trouble with the button above, copy and paste the URL below into your web browser:</p>
        <p><a href="#{assigns.url}">#{assigns.url}</a></p>
        <p>If you didn't create an account with us, please ignore this email.</p>
        """

      "reset_password_instructions" ->
        """
        <h1>Hi #{assigns.user.email},</h1>
        <p>You can reset your password by clicking the button below:</p>
        <div style="text-align: center;">
          <a href="#{assigns.url}" class="button">Reset Password</a>
        </div>
        <p>If you're having trouble with the button above, copy and paste the URL below into your web browser:</p>
        <p><a href="#{assigns.url}">#{assigns.url}</a></p>
        <p>If you didn't request this change, please ignore this email.</p>
        """

      "update_email_instructions" ->
        """
        <h1>Hi #{assigns.user.email},</h1>
        <p>You can change your email by clicking the button below:</p>
        <div style="text-align: center;">
          <a href="#{assigns.url}" class="button">Update Email</a>
        </div>
        <p>If you're having trouble with the button above, copy and paste the URL below into your web browser:</p>
        <p><a href="#{assigns.url}">#{assigns.url}</a></p>
        <p>If you didn't request this change, please ignore this email.</p>
        """

      "company_invitation" ->
        """
        <h1>Hello,</h1>
        <p>You have been invited to join <strong>#{assigns.company.name}</strong> on #{app_name}.</p>
        <div style="text-align: center;">
          <a href="#{assigns.invitation_url}" class="button">Accept Invitation</a>
        </div>
        <p>If you're having trouble with the button above, copy and paste the URL below into your web browser:</p>
        <p><a href="#{assigns.invitation_url}">#{assigns.invitation_url}</a></p>
        <p>If you weren't expecting this invitation, you can safely ignore this email.</p>
        """

      "contact_form_email" ->
        user_id_info = if assigns[:user_id] do
          "<p><strong>Submitted by registered user ID:</strong> #{assigns.user_id}</p>"
        else
          "<p><strong>Submitted by:</strong> Unregistered visitor</p>"
        end

        """
        <h1>New Contact Form Submission</h1>
        <div class="message-box">
          <p><strong>From:</strong> #{assigns.name} (#{assigns.email})</p>
          <p><strong>Subject:</strong> #{assigns.subject}</p>
          #{user_id_info}
        </div>

        <h3>Message:</h3>
        <div class="message-box">
          <p>#{assigns.message}</p>
        </div>
        """

      "offline_support_notification" ->
        """
        <h1>New Chat Message While Support Offline</h1>
        <div class="message-box">
          <p>A customer has sent a message while support is offline:</p>
        </div>

        <div class="message-box" style="border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; background-color: #f9fafb;">
          <h3 style="margin-top: 0; color: #374151;">Customer Information</h3>
          <p><strong>Name:</strong> #{assigns.customer_name}</p>
          <p><strong>Email:</strong> #{assigns.customer_email}</p>
          <p><strong>Session ID:</strong> #{assigns.session_id}</p>
        </div>

        <h3>Message:</h3>
        <div class="message-box" style="border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; background-color: white;">
          <p>#{assigns.message_content}</p>
        </div>

        <div style="text-align: center; margin: 20px 0;">
          <a href="#{assigns.chat_url}" class="button">View in Admin Panel</a>
        </div>

        <p><strong>Please respond as soon as possible to maintain good customer service.</strong></p>
        """

      "contact_form_confirmation" ->
        """
        <h1>Thank you for contacting us</h1>
        <p>Hi #{assigns.name},</p>
        <p>Thank you for reaching out to us. This is a confirmation that we have received your message:</p>

        <div class="message-box">
          <p><strong>Subject:</strong> #{assigns.subject}</p>
        </div>

        <p>Our team will review your message and get back to you as soon as possible.</p>
        <p>Thanks for your patience!</p>
        """
    end

    # Determine email title and recipient
    title = case assigns[:template] do
      "confirmation_instructions" -> "Confirmation instructions"
      "reset_password_instructions" -> "Reset password instructions"
      "update_email_instructions" -> "Update email instructions"
      "company_invitation" -> "Invitation to join #{assigns.company.name}"
      "contact_form_email" -> "Contact Form: #{assigns.subject}"
      "contact_form_confirmation" -> "Thank you for contacting us"
      "chat_transcript" -> "Your Chat Transcript"
      "offline_support_notification" -> "New Chat Message While Support Offline"
    end

    recipient_email = cond do
      Map.has_key?(assigns, :recipient_email) -> assigns.recipient_email
      Map.has_key?(assigns, :user) -> assigns.user.email
      Map.has_key?(assigns, :email) -> assigns.email
      true -> "recipient"
    end

    email_layout(title, content, app_name, year, recipient_email)
  end

  # Direct template rendering approach
  def deliver_confirmation_instructions(user, url) do
    template_assigns = %{
      template: "confirmation_instructions",
      user: user,
      url: url,
      app_name: app_name(),
      year: DateTime.utc_now().year
    }

    text_body = """
    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """

    deliver(user.email, "Confirmation instructions", text_body, render_email_template(template_assigns))
  end

  def deliver_reset_password_instructions(user, url) do
    template_assigns = %{
      template: "reset_password_instructions",
      user: user,
      url: url,
      app_name: app_name(),
      year: DateTime.utc_now().year
    }

    text_body = """
    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """

    deliver(user.email, "Reset password instructions", text_body, render_email_template(template_assigns))
  end

  def deliver_update_email_instructions(user, url) do
    template_assigns = %{
      template: "update_email_instructions",
      user: user,
      url: url,
      app_name: app_name(),
      year: DateTime.utc_now().year
    }

    text_body = """
    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """

    deliver(user.email, "Update email instructions", text_body, render_email_template(template_assigns))
  end

  def deliver_company_invitation(email, company, invitation_url) do
    template_assigns = %{
      template: "company_invitation",
      company: company,
      invitation_url: invitation_url,
      app_name: app_name(),
      year: DateTime.utc_now().year,
      recipient_email: email
    }

    text_body = """
    ==============================

    Hi,

    You have been invited to join #{company.name} on #{app_name()}.

    You can accept this invitation by visiting the URL below:

    #{invitation_url}

    If you weren't expecting this invitation, you can safely ignore this email.

    ==============================
    """

    deliver(email, "Invitation to join #{company.name}", text_body, render_email_template(template_assigns))
  end

  @doc """
  Deliver contact form submission email.

  Sends the contents of the contact form to the admin email address
  and includes information about the sender.
  """
  def deliver_contact_form_email(email, name, subject, message, user_id) do
    admin_email = "admin@example.com" # Replace with actual admin email

    # Email to admin
    admin_template_assigns = %{
      template: "contact_form_email",
      name: name,
      email: email,
      subject: subject,
      message: message,
      user_id: user_id,
      app_name: app_name(),
      year: DateTime.utc_now().year,
      recipient_email: admin_email
    }

    admin_text_body = """
    ==============================

    New contact form submission:

    From: #{name} (#{email})
    Subject: #{subject}
    #{if user_id, do: "\nSubmitted by registered user ID: #{user_id}", else: "\nSubmitted by unregistered visitor"}

    Message:
    #{message}

    ==============================
    """

    admin_subject = "Contact Form: #{subject}"
    deliver(admin_email, admin_subject, admin_text_body, render_email_template(admin_template_assigns))

    # Confirmation email to user
    user_template_assigns = %{
      template: "contact_form_confirmation",
      name: name,
      subject: subject,
      app_name: app_name(),
      year: DateTime.utc_now().year,
      recipient_email: email
    }

    user_text_body = """
    ==============================

    Hi #{name},

    Thank you for contacting us. This is a confirmation that we have received your message:

    Subject: #{subject}

    Our team will review your message and get back to you as soon as possible.

    ==============================
    """

    user_subject = "Thank you for contacting us"
    deliver(email, user_subject, user_text_body, render_email_template(user_template_assigns))
  end

  @doc """
  Deliver offline support notification to support team.

  Sends an email to the support team when a user sends a message while support is offline.
  """
  def deliver_offline_support_notification(customer_email, customer_name, message_content, session_id) do
    current_app_name = app_name()
    year = DateTime.utc_now().year
    current_support_email = support_email()

    # Create template assigns
    template_assigns = %{
      template: "offline_support_notification",
      app_name: current_app_name,
      year: year,
      customer_email: customer_email,
      customer_name: customer_name,
      message_content: message_content,
      session_id: session_id,
                chat_url: "#{EndpointHelper.admin_url()}/dashboard/chat",
      recipient_email: current_support_email
    }

    # Plain text version
    text_body = """
    ==============================

    New Chat Message Received While Support Offline

    A customer has sent a message while support is offline:

    Customer: #{customer_name} (#{customer_email})
    Session ID: #{session_id}
    Message: #{String.slice(message_content, 0, 200)}#{if String.length(message_content) > 200, do: "...", else: ""}

    Please respond as soon as possible.

    View in admin panel: #{template_assigns.chat_url}

    ==============================
    """

    # HTML content is handled in render_email_template
    content = render_email_template(template_assigns)

    # Send the email
    deliver(current_support_email, "New Chat Message While Support Offline - Session ##{session_id}", text_body, content)
  end

  @doc """
  Deliver chat transcript email.

  Sends the chat transcript to the user when a chat session is closed.
  """
  def deliver_chat_transcript(email, session_id) do
    # Get the chat session with messages
    session = Core.Chat.get_session_with_messages(session_id)

    # Generate the transcript
    transcript = Core.Chat.generate_transcript(session_id)

    # Format the transcript for HTML display
    formatted_transcript =
      transcript
      |> String.split("\n")
      |> Enum.filter(fn line ->
        # Skip the header line with the date
        not String.starts_with?(line, "Chat Transcript - ")
      end)
      |> Enum.map(fn line ->
        # Check if it's a message line with timestamp
        if String.starts_with?(line, "[") do
          # Extract parts: "[timestamp] sender: content"
          case Regex.run(~r/\[(.*?)\] (.*?): (.*)/, line) do
            [_, timestamp, sender, content] ->
              is_admin = sender == "Support Agent"
              # Extract just the time part from the timestamp (HH:MM:SS)
              # Format as HH:MM by removing seconds
              time = timestamp
                |> String.split(" ")
                |> List.last()
                |> String.split(":")
                |> Enum.take(2)
                |> Enum.join(":")

              # Create a simple message bubble with content and time-name below
              bg_color = if is_admin, do: "#f3f4f6", else: "#e6f0fd"
              text_color = "#374151"

              # Create a message bubble with width based on content, positioned to the left
              "<div style=\"margin-bottom: 16px; text-align: left;\">" <>
              "  <div style=\"display: inline-block; padding: 10px 12px; border-radius: 12px; background-color: #{bg_color}; color: #{text_color};\">" <>
              "    <div style=\"font-size: 14px;\">#{content}</div>" <>
              "  </div>" <>
              "  <div style=\"font-size: 10px; color: #6b7280; margin-top: 4px;\">#{time} - #{sender}</div>" <>
              "</div>"
            _ -> "<div>#{line}</div>"
          end
        else
          "" # Skip header lines
        end
      end)
      |> Enum.join("\n")

    # Determine recipient name
    recipient_name = cond do
      session.anonymous_name -> session.anonymous_name
      session.user_id ->
        user = Core.Repo.get(Core.Accounts.User, session.user_id)
        user && (user.first_name || user.email) || "User"
      true -> "User"
    end

    # Create template assigns
    template_assigns = %{
      template: "chat_transcript",
      recipient_name: recipient_name,
      transcript: formatted_transcript,
      session_id: session.id,
      started_at: session.started_at,
      ended_at: session.ended_at,
      app_name: app_name(),
      year: DateTime.utc_now().year,
      recipient_email: email
    }

    # Plain text version
    text_body = """
    ==============================

    Hi #{recipient_name},

    Thank you for chatting with us. Below is a transcript of your conversation:

    Session ID: #{session.id}
    Started: #{Calendar.strftime(session.started_at, "%B %d, %Y at %I:%M %p")}
    #{if session.ended_at, do: "Ended: #{Calendar.strftime(session.ended_at, "%B %d, %Y at %I:%M %p")}", else: ""}

    #{transcript}

    ==============================
    """

    # Add chat transcript template to the case statement in render_email_template
    content = case template_assigns[:template] do
      "chat_transcript" ->
        """
        <h2>Hi #{template_assigns.recipient_name},</h2>
        <p>Thank you for chatting with us. Below is a transcript of your conversation:</p>

        <div class="info-container" style="border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; background-color: #f9fafb; margin-top: 16px; margin-bottom: 8px;">
          <h3 style="margin-top: 0; margin-bottom: 12px; color: #374151; font-size: 16px;">Session Information</h3>
          <div class="info-grid" style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
            <div class="info-item">
              <div style="font-size: 14px; color: #6b7280; margin-bottom: 4px;">Started At</div>
              <div style="font-size: 16px;">#{Calendar.strftime(template_assigns.started_at, "%B %d, %Y at %I:%M %p")}</div>
            </div>
            #{if template_assigns.ended_at do
              ~s(<div class="info-item">
                <div style="font-size: 14px; color: #6b7280; margin-bottom: 4px;">Ended At</div>
                <div style="font-size: 16px;">#{Calendar.strftime(template_assigns.ended_at, "%B %d, %Y at %I:%M %p")}</div>
              </div>)
            else
              ""
            end}
          </div>
        </div>

        <div class="chat-container" style="border: 1px solid #e5e7eb; border-radius: 8px; background-color: #f9fafb;">
          <div class="chat-header" style="background-color: #f3f4f6; padding: 12px 16px; border-bottom: 1px solid #e5e7eb; border-top-left-radius: 8px; border-top-right-radius: 8px;">
            <h3 style="margin: 0; color: #374151; font-size: 16px;">Chat Transcript</h3>
          </div>

          <div class="message-box" style="background-color: white; padding: 12px;">
            #{template_assigns.transcript}
          </div>
        </div>

        <p>If you have any further questions, please don't hesitate to contact us.</p>
        """
      _ ->
        render_email_template(template_assigns)
    end

    # Send the email
    deliver(email, "Your Chat Transcript", text_body, email_layout("Your Chat Transcript", content, template_assigns.app_name, template_assigns.year, email))
  end

  # Delivers the email using the application mailer with HTML support
  defp deliver(recipient, subject, text_body, html_body) do
    email =
      new()
      |> to(recipient)
      |> from({app_name(), app_email()})
      |> subject(subject)
      |> text_body(text_body)

    email =
      if html_body do
        # Process HTML with Premailex to inline CSS for better email client compatibility
        processed_html = Premailex.to_inline_css(html_body)

        email |> html_body(processed_html)
      else
        email
      end

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}
      {:error, reason} ->
        Logger.warning("Sending email failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
