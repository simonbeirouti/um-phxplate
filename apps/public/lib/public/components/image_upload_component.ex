defmodule Public.Components.Upload.ImageUploadComponent do
  @moduledoc """
  LiveComponent for handling image uploads with S3 integration.

  This component provides a complete UI for uploading, previewing, and managing
  profile images, logos, or other image types. It integrates with AWS S3 for
  storage and handles the complete lifecycle of image upload, validation, and
  replacement of existing images.

  ## Props
  - `:type` - The type of image being uploaded (e.g., :avatar, :logo)
  - `:image_url` - Current image URL (optional)
  - `:on_upload_complete` - Event name to emit when upload completes
  - `:entity_type` - The entity type this image belongs to (e.g., :user, :company)
  - `:entity_id` - The ID of the entity

  ## Examples
      <.live_component
        module={ImageUploadComponent}
        id="profile-avatar"
        type={:avatar}
        image_url={@user.profile.avatar_url}
        entity_type={:user}
        entity_id={@user.id}
        on_upload_complete="image_uploaded"
      />
  """
  use Public, :live_component
  alias Core.AWS.S3
  require Logger

  @doc """
  Initializes the component with file upload capabilities.

  Sets up the upload configuration with appropriate file type restrictions,
  size limits, and upload handling.
  """
  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:uploaded_files, [])
     |> allow_upload(:image,
       accept: ~w(.jpg .jpeg .png .gif),
       max_entries: 1,
       max_file_size: 5_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @doc """
  Updates the component with the provided assigns.

  Sets default values for optional attributes if they're not provided.
  """
  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:on_upload_complete, fn -> "image_uploaded" end)
      |> assign_new(:entity_type, fn -> :generic end)
      |> assign_new(:entity_id, fn -> nil end)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    socket = handle_uploads(socket)
    {:noreply, socket}
  end

  # Handle file uploads
  defp handle_uploads(socket) do
    consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
      result = upload_to_s3(socket, path, entry)

      # Send the event to the parent LiveView
      send_upload_result_to_parent(socket, result)

      result
    end)

    socket
  end

  defp upload_to_s3(socket, path, entry) do
    # Use replace_file to delete the old image if there is one
    case S3.replace_file(
           %{path: path, filename: entry.client_name},
           socket.assigns.type,
           socket.assigns[:image_url],
           content_type: entry.client_type
         ) do
      {:ok, url} ->
        {:ok, url}

      {:error, reason} ->
        Logger.error("Failed to upload: #{inspect(reason)}")
        {:error, "Failed to upload: #{inspect(reason)}"}
    end
  end

  defp send_upload_result_to_parent(socket, {:ok, url}) do
    send(self(), {
      String.to_atom(socket.assigns.on_upload_complete),
      %{
        type: socket.assigns.type,
        url: url,
        old_url: socket.assigns[:image_url],
        entity_type: socket.assigns.entity_type,
        entity_id: socket.assigns.entity_id
      }
    })
  end

  defp send_upload_result_to_parent(socket, {:error, error_msg}) do
    send(self(), {
      String.to_atom("#{socket.assigns.on_upload_complete}_error"),
      %{
        type: socket.assigns.type,
        error: error_msg,
        entity_type: socket.assigns.entity_type,
        entity_id: socket.assigns.entity_id
      }
    })
  end

  # Handle upload progress with logging
  defp handle_progress(:image, entry, socket) do
    if entry.done? do
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp error_to_string(:too_large), do: "File is too large (max 5MB)"
  defp error_to_string(:not_accepted), do: "File type not accepted (allowed: jpg, jpeg, png, gif)"
  defp error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp error_to_string(err), do: "Error: #{inspect(err)}"

  @doc """
  Renders the image upload component with preview, validation, and controls.

  Displays the current image or a default, shows upload progress and validation errors,
  and provides buttons to confirm or cancel uploads.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="form-control w-full">
      <form phx-submit="save" phx-change="validate" phx-target={@myself}>
        <div class="flex items-center gap-6">
          <!-- Image Preview with Upload Area -->
          <div class="relative" phx-drop-target={@uploads.image.ref}>
            <div class="avatar">
              <div class="w-32 h-32 rounded-full ring ring-base-300 ring-offset-base-100 ring-offset-2">
                <%= if Enum.any?(@uploads.image.entries) do %>
                  <.live_img_preview
                    entry={hd(@uploads.image.entries)}
                    class="w-full h-full object-cover rounded-full"
                  />
                <% else %>
                  <img
                    src={@image_url || "/images/avatar.jpg"}
                    alt="Profile Image"
                    class="w-full h-full object-cover rounded-full"
                  />
                <% end %>
              </div>

    <!-- Upload Overlay -->
              <div class="absolute inset-0 rounded-full bg-black/50 opacity-0 hover:opacity-100 transition-opacity duration-200 flex items-center justify-center cursor-pointer">
                <div class="relative w-full h-full flex items-center justify-center">
                  <.icon name="hero-camera" class="w-8 h-8 text-white pointer-events-none" />
                  <.live_file_input
                    upload={@uploads.image}
                    class="absolute inset-0 opacity-0 cursor-pointer w-full h-full rounded-full"
                  />
                </div>
              </div>
            </div>

    <!-- Upload Errors -->
            <%= for err <- upload_errors(@uploads.image) do %>
              <div class="alert alert-error mt-2 text-sm">
                <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                <span>{error_to_string(err)}</span>
              </div>
            <% end %>
          </div>

    <!-- Upload Actions -->
          <%= if Enum.any?(@uploads.image.entries) do %>
            <div class="flex flex-col gap-3">
              <%= for entry <- @uploads.image.entries do %>
                <div class="card bg-base-200 shadow-sm">
                  <div class="card-body p-4">
                    <div class="flex flex-col gap-3">
                      <!-- File Info -->
                      <div class="text-sm">
                        <p class="font-medium text-base-content">{entry.client_name}</p>
                        <p class="text-base-content/70">
                          {Float.round(entry.client_size / 1024 / 1024, 2)} MB
                        </p>
                      </div>

    <!-- Progress Bar -->
                      <%= if entry.progress < 100 do %>
                        <div class="w-full">
                          <div class="flex justify-between text-xs text-base-content/70 mb-1">
                            <span>Uploading...</span>
                            <span>{entry.progress}%</span>
                          </div>
                          <progress
                            class="progress progress-primary w-full"
                            value={entry.progress}
                            max="100"
                          >
                          </progress>
                        </div>
                      <% end %>

    <!-- Action Buttons -->
                      <div class="flex gap-2">
                        <button
                          type="button"
                          phx-click="cancel-upload"
                          phx-value-ref={entry.ref}
                          phx-target={@myself}
                          class="btn btn-error btn-sm flex-1"
                        >
                          <.icon name="hero-x-mark" class="w-4 h-4" /> Cancel
                        </button>

                        <button
                          type="submit"
                          class="btn btn-primary btn-sm flex-1"
                          phx-disable-with="Uploading..."
                          disabled={entry.progress < 100}
                        >
                          <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> Confirm
                        </button>
                      </div>

    <!-- Entry Errors -->
                      <%= for err <- upload_errors(@uploads.image, entry) do %>
                        <div class="alert alert-error text-xs">
                          <.icon name="hero-exclamation-circle" class="w-3 h-3" />
                          <span>{error_to_string(err)}</span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <!-- Upload Instructions -->
            <div class="text-base-content/70">
              <p class="text-sm font-medium mb-1">Click or drag to upload</p>
              <p class="text-xs">JPG, PNG, GIF up to 5MB</p>
            </div>
          <% end %>
        </div>
      </form>
    </div>
    """
  end
end
