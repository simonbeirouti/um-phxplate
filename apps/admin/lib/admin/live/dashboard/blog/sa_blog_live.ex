defmodule Admin.BlogsLive do
  @moduledoc """
  LiveView for blog management.

  This view provides functionality for creating, reading, updating, and deleting blog posts.
  It features a list of blog posts with pagination and a tabbed detail view for viewing,
  editing, and managing posts.
  """
  use Admin, :live_view
  alias Core.Blog
  alias Core.Blog.Post
  alias Admin.PageMeta
  alias Phoenix.LiveView.JS
  import Admin.CoreComponents
  alias Admin.Components.ActivityTimelineComponent
  alias Core.PubSub.DataSync
  alias Admin.Components.Markdown

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("blog_posts", "all")
    end

    socket =
      socket
      |> assign(:selected_post, nil)
      |> assign(:changeset, nil)
      |> assign(:delete_confirmation, false)
      |> assign(:new_post_changeset, Blog.change_post(%Post{}))
      |> assign(:post_activities, [])
      |> assign(:show_drawer, false)
      |> assign(:form_changed, false)
      |> assign(:show_new_post_form, false)
      |> assign(:new_post_form_mode, "dialog")

    {:ok, load_posts(socket, 1)}
  end

  defp load_posts(socket, page) do
    per_page = 10

    # Since only super admins can access this page, show all posts
    posts = Blog.list_posts(page: page, per_page: per_page, published_only: false)
    total_posts = Blog.count_posts(published_only: false)
    total_pages = max(1, ceil(total_posts / per_page))

    socket
    |> assign(:posts, posts)
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:per_page, per_page)
    |> PageMeta.assign_metadata(
      title: "Blog Management",
      description: "Blog posts and articles",
      url: "/dashboard/blog"
    )
  end

  @impl true
  def handle_event("select_post", %{"id" => post_id}, socket) do
    post = Blog.get_post!(post_id)
    changeset = Blog.change_post(post)
    activities = Core.Tracking.get_blog_post_activities(post_id, 20)

    {:noreply,
     assign(socket,
       selected_post: post,
       changeset: changeset,
       post_activities: activities,
       show_drawer: true
     )}
  end

  def handle_event("open_new_post_dialog", _params, socket) do
    changeset = Blog.change_post(%Post{})
    {:noreply, assign(socket, new_post_changeset: changeset, show_new_post_form: true)}
  end

  def handle_event("set_screen_mode", %{"mode" => mode}, socket) do
    # Only update the mode without changing visibility
    {:noreply, assign(socket, new_post_form_mode: mode)}
  end

  def handle_event("create_post", %{"post" => post_params}, socket) do
    case Blog.create_post(post_params, socket.assigns.current_user) do
      {:ok, _post} ->
        socket =
          socket
          |> put_flash(:info, "Post created successfully.")
          |> assign(show_new_post_form: false)
          |> assign(new_post_changeset: Blog.change_post(%Post{}))
          |> load_posts(1)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, new_post_changeset: changeset)}
    end
  end

  def handle_event("validate_new_post", %{"post" => post_params}, socket) do
    changeset =
      %Post{}
      |> Blog.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, new_post_changeset: changeset)}
  end

  def handle_event(
        "save_post",
        %{"post" => post_params},
        %{assigns: %{current_user: current_user, selected_post: selected_post}} = socket
      ) do
    save_post(socket, selected_post, post_params, current_user)
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, show_new_post_form: false)}
  end

  def handle_event("validate", %{"post" => post_params}, socket) do
    original_data = %{
      "title" => socket.assigns.selected_post.title || "",
      "slug" => socket.assigns.selected_post.slug || "",
      "description" => socket.assigns.selected_post.description || "",
      "content" => socket.assigns.selected_post.content || ""
    }

    # Check if form has changed
    form_changed = post_params != original_data

    changeset =
      socket.assigns.selected_post
      |> Blog.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset, form_changed: form_changed)}
  end

  def handle_event("delete_post", _params, socket) do
    {:noreply, assign(socket, :delete_confirmation, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_confirmation, false)}
  end

  def handle_event(
        "confirm_delete_post",
        _params,
        %{assigns: %{current_user: current_user, selected_post: selected_post}} = socket
      ) do
    case Blog.delete_post(selected_post, current_user) do
      {:ok, _deleted_post} ->
        socket =
          socket
          |> put_flash(:info, "Post deleted successfully.")
          |> assign(
            selected_post: nil,
            changeset: nil,
            delete_confirmation: false,
            post_activities: []
          )

        {:noreply, socket}

      {:error, :unauthorized} ->
        socket =
          socket
          |> put_flash(:error, "You are not authorized to delete this post.")
          |> assign(:delete_confirmation, false)

        {:noreply, socket}
    end
  end

  def handle_event("update_status", %{"status" => status, "post_id" => post_id}, socket) do
    status = String.to_existing_atom(status)
    post = Blog.get_post!(post_id)

    case Blog.update_post(post, %{published: status}, socket.assigns.current_user) do
      {:ok, updated_post} ->
        changeset = Blog.change_post(updated_post)

        socket =
          socket
          |> assign(:selected_post, updated_post)
          |> assign(:changeset, changeset)
          |> load_posts(socket.assigns.page)
          |> put_flash(:info, "Post status updated successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update post status")}
    end
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    {:noreply, load_posts(socket, page)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, show_drawer: false)}
  end

  def handle_event("reset_post", _params, socket) do
    changeset = Blog.change_post(socket.assigns.selected_post)
    {:noreply, assign(socket, changeset: changeset, form_changed: false)}
  end

  @impl true
  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    socket = update(socket, :layout_data, &Map.put(&1, :current_path, uri.path))
    {:noreply, socket}
  end

  defp save_post(socket, %Post{id: nil}, post_params, current_user) do
    case Blog.create_post(post_params, current_user) do
      {:ok, post} ->
        activities = Core.Tracking.get_blog_post_activities(post.id, 20)
        changeset = Blog.change_post(post)

        socket =
          socket
          |> put_flash(:info, "Post created successfully.")
          |> assign(
            selected_post: post,
            changeset: changeset,
            post_activities: activities,
            form_changed: false
          )

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to create posts.")}
    end
  end

  defp save_post(socket, %Post{id: id} = post, post_params, current_user)
       when is_binary(id) or is_integer(id) do
    case Blog.update_post(post, post_params, current_user) do
      {:ok, updated_post} ->
        activities = Core.Tracking.get_blog_post_activities(updated_post.id, 20)
        changeset = Blog.change_post(updated_post)

        socket =
          socket
          |> put_flash(:info, "Post updated successfully.")
          |> assign(
            selected_post: updated_post,
            changeset: changeset,
            post_activities: activities,
            form_changed: false
          )

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to update posts.")}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :page_id, "blog-live-view")

    ~H"""
    <div class="flex-1 h-[calc(100vh-100px)]" id={@page_id}>
      <.header>
        Blog Management
        <:subtitle>View and manage blog posts</:subtitle>
        <:actions>
          <button phx-click="open_new_post_dialog" class="btn btn-neutral">
            <.icon name="hero-plus" class="-ml-0.5 mr-2 h-4 w-4" />
            New Post
          </button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-3 lg:gap-8 mt-4 h-[calc(100vh-200px)]">
        <div class="h-[calc(100vh-200px)] col-span-1">
          <h2 class="text-xl font-semibold mb-4">Posts</h2>

          <%= if Enum.empty?(@posts) do %>
            <div class="p-4 bg-gray-50 rounded-md">
              <p class="text-gray-500 text-center">No posts available yet</p>
              <p class="text-gray-500 text-center mt-2">
                Click "New Post" to create your first blog post
              </p>
            </div>
          <% else %>
            <div class="divide-y">
              <%= for post <- @posts do %>
                <div
                  class={"cursor-pointer p-3 rounded-md hover:bg-gray-50 relative #{if @selected_post && @selected_post.id == post.id, do: "bg-gray-100 border-l-4 border-blue-500", else: ""}"}
                  phx-click="select_post"
                  phx-value-id={post.id}
                >
                  <!-- Post content -->
                  <div class="flex justify-between items-center">
                    <h4 class="text-sm font-medium text-gray-900">{post.title}</h4>
                    <span class={[
                      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                      case post.published do
                        :published -> "bg-green-100 text-green-800"
                        :draft -> "bg-yellow-100 text-yellow-800"
                        :unpublished -> "bg-gray-100 text-gray-800"
                      end
                    ]}>
                      {post.published}
                    </span>
                  </div>
                  <div class="mt-1">
                    <p class="text-xs text-gray-500">
                      Created: {Calendar.strftime(post.inserted_at, "%B %d, %Y at %H:%M")}
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>

          <%= if @total_pages > 1 do %>
            <div class="mt-6">
              <div class="join w-full flex justify-center items-center">
                <%= if @page > 1 do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={@page - 1}>
                    <.icon name="hero-arrow-left" class="w-3.5 h-3.5" />
                  </button>
                <% end %>

                <%= for page_num <- max(1, @page - 2)..min(@total_pages, @page + 2) do %>
                  <button
                    class={"join-item btn #{if page_num == @page, do: "btn-active"}"}
                    phx-click="paginate"
                    phx-value-page={page_num}
                  >
                    {page_num}
                  </button>
                <% end %>

                <%= if @page < @total_pages do %>
                  <button class="join-item btn" phx-click="paginate" phx-value-page={@page + 1}>
                    <.icon name="hero-arrow-right" class="w-3.5 h-3.5" />
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

    <!-- Desktop Details View (hidden on mobile) -->
        <div class="hidden lg:block col-span-2 overflow-y-auto">
          <h2 class="text-xl font-semibold mb-4">Post Details</h2>
          <%= if @selected_post do %>
            {render_post_details(assign(assigns, :context, "desktop"))}
          <% else %>
            <p class="text-gray-500">Select a post to view details</p>
          <% end %>
        </div>
      </div>

    <!-- Mobile Drawer -->
      <div class="lg:hidden">
        <div class={["drawer", "drawer-bottom", (@show_drawer and @selected_post != nil) && "drawer-open"]}>
          <input id="mobile-post-drawer" type="checkbox" class="drawer-toggle" checked={@show_drawer and @selected_post != nil} />
          <div class="drawer-content">
            <!-- Page content here -->
          </div>
          <div class="drawer-side">
            <label for="mobile-post-drawer" class="drawer-overlay" phx-click="close_drawer"></label>
            <div class="menu p-4 w-full h-3/4 bg-base-200 text-base-content">
              <h2 class="text-lg font-bold">Post Details</h2>
              <%= if @selected_post do %>
                <p class="text-sm mb-4">{@selected_post.title}</p>
              <% end %>
              <%= if @selected_post do %>
                <%= render_post_details(assign(assigns, :context, "mobile")) %>
              <% end %>
            </div>
          </div>
        </div>
      </div>

    <!-- New Post Dialog/Drawer -->
      <dialog id="new-post-modal" class={["modal", @show_new_post_form && "modal-open"]}>
        <div class="modal-box">
          <h3 class="font-bold text-lg">Create New Post</h3>
          <p class="py-4">Create a new blog post. You can edit additional details after creation.</p>
          <div class="relative grid gap-4 border-none">
            <form
              id="new-post-form"
              phx-change="validate_new_post"
              phx-submit="create_post"
              class="space-y-4"
              phx-hook="ResetForm"
            >
              <div class="flex flex-col">
                <label for="title" class="label"><span class="label-text">Title</span></label>
                <input
                  type="text"
                  id="title"
                  name="post[title]"
                  value={Ecto.Changeset.get_field(@new_post_changeset, :title) || ""}
                  placeholder="Enter post title"
                  class="input input-bordered w-full text-base"
                  required
                />
                <%= if @new_post_changeset.errors[:title] do %>
                  <p class="text-sm text-red-600 mt-1 capitalize">
                    {elem(@new_post_changeset.errors[:title], 0)}
                  </p>
                <% end %>
              </div>

              <div class="flex flex-col">
                <label for="description" class="label"><span class="label-text">Description</span></label>
                <input
                  type="text"
                  id="description"
                  name="post[description]"
                  value={Ecto.Changeset.get_field(@new_post_changeset, :description) || ""}
                  placeholder="Brief description of the post"
                  class="input input-bordered w-full text-base"
                />
                <%= if @new_post_changeset.errors[:description] do %>
                  <p class="text-sm text-red-600 mt-1 capitalize">
                    {elem(@new_post_changeset.errors[:description], 0)}
                  </p>
                <% end %>
              </div>

              <div class="flex flex-col">
                <label for="content" class="label"><span class="label-text">Content</span></label>
                <textarea
                  id="content"
                  name="post[content]"
                  value={Ecto.Changeset.get_field(@new_post_changeset, :content) || ""}
                  placeholder="Write your post content here..."
                  rows="8"
                  class="textarea textarea-bordered w-full text-base"
                  required
                ></textarea>
                <%= if @new_post_changeset.errors[:content] do %>
                  <p class="text-sm text-red-600 mt-1 capitalize">
                    {elem(@new_post_changeset.errors[:content], 0)}
                  </p>
                <% end %>
              </div>

              <div class="flex flex-col gap-2 mt-4">
                <button class="btn btn-neutral w-full" type="submit">Save</button>
                <button class="btn btn-outline w-full" phx-click="cancel">Cancel</button>
              </div>
            </form>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop" phx-click="cancel">
          <button>close</button>
        </form>
      </dialog>
    </div>
    """
  end

  # Extract the post details rendering into a separate function for reuse
  defp render_post_details(assigns) do
    # Add a context to make component IDs unique
    context = assigns[:context] || "desktop"
    assigns = assign(assigns, :context, context)

    ~H"""
    <div role="tablist" class="tabs tabs-lifted">
      <input type="radio" name="post_tabs_#{@context}" role="tab" class="tab" aria-label="View" checked />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <div class="space-y-6 bg-base-100 rounded-md p-2">
          <div>
            <h3 class="text-2xl font-bold mb-2">{@selected_post.title}</h3>

            <%= if @selected_post.description do %>
              <p class="text-base-content/70 italic mb-4">{@selected_post.description}</p>
            <% end %>

            <div class="prose max-w-none">
              <Markdown.to_html content={@selected_post.content} />
            </div>
          </div>
        </div>
      </div>

      <input type="radio" name="post_tabs_#{@context}" role="tab" class="tab" aria-label="Edit" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <.form
          for={@changeset || Blog.change_post(@selected_post)}
          id={"post-form-#{@context}"}
          phx-change="validate"
          phx-submit="save_post"
          class="p-2"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="space-y-2 col-span-1">
              <label class="label" for={"post_title_#{@context}"}>
                <span class="label-text">Title</span>
              </label>
              <input
                type="text"
                id={"post_title_#{@context}"}
                name="post[title]"
                value={
                  Ecto.Changeset.get_field(
                    @changeset || Blog.change_post(@selected_post),
                    :title
                  ) || ""
                }
                placeholder="Post title"
                class="input input-bordered w-full text-base"
                required
              />
            </div>

            <div class="space-y-2 col-span-1">
              <label class="label" for={"post_slug_#{@context}"}>
                <span class="label-text">Slug</span>
              </label>
              <input
                type="text"
                id={"post_slug_#{@context}"}
                name="post[slug]"
                value={
                  Ecto.Changeset.get_field(
                    @changeset || Blog.change_post(@selected_post),
                    :slug
                  ) || ""
                }
                placeholder="url-friendly-slug"
                class="input input-bordered w-full text-base"
              />
            </div>

            <div class="space-y-2 col-span-2">
              <label class="label" for={"post_description_#{@context}"}>
                <span class="label-text">Description</span>
              </label>
              <input
                type="text"
                id={"post_description_#{@context}"}
                name="post[description]"
                value={
                  Ecto.Changeset.get_field(
                    @changeset || Blog.change_post(@selected_post),
                    :description
                  ) || ""
                }
                placeholder="Brief description of the post"
                class="input input-bordered w-full text-base"
              />
            </div>

            <div class="space-y-2 col-span-2">
              <label class="label" for={"post_content_#{@context}"}>
                <span class="label-text">Content</span>
              </label>
              <textarea
                id={"post_content_#{@context}"}
                name="post[content]"
                placeholder="Write your post content here..."
                rows="10"
                class="textarea textarea-bordered w-full text-base"
                required
              ><%= Ecto.Changeset.get_field(@changeset || Blog.change_post(@selected_post), :content) || "" %></textarea>
            </div>

            <%= if @form_changed do %>
              <div class="pt-5 col-span-2">
                <div class="flex flex-col gap-3 lg:flex-row lg:justify-end lg:gap-3">
                  <button
                    type="button"
                    phx-click="reset_post"
                    class="btn btn-outline w-full lg:w-auto"
                  >
                    Reset
                  </button>
                  <button type="submit" class="btn btn-primary w-full lg:w-auto">
                    Save Changes
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </.form>
      </div>

      <input type="radio" name="post_tabs_#{@context}" role="tab" class="tab" aria-label="Settings" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <div class="space-y-4 pt-4 px-2">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <h4 class="text-sm font-medium text-base-content/70">Publication Status</h4>
              <form phx-change="update_status" class="mt-2">
                <select
                  id={"status-select-#{@context}"}
                  name="status"
                  class="select select-bordered capitalize w-[180px]"
                >
                  <option value="published" selected={@selected_post.published == :published}>
                    Published
                  </option>
                  <option value="draft" selected={@selected_post.published == :draft}>Draft</option>
                  <option value="unpublished" selected={@selected_post.published == :unpublished}>
                    Unpublished
                  </option>
                </select>
                <input type="hidden" name="post_id" value={@selected_post.id} />
              </form>
            </div>
            <div>
              <h4 class="text-sm font-medium text-base-content/70">Created</h4>
              <p class="mt-1">
                {Calendar.strftime(@selected_post.inserted_at, "%B %d, %Y at %I:%M %p")}
              </p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-base-content/70">Last Updated</h4>
              <p class="mt-1">
                {Calendar.strftime(@selected_post.updated_at, "%B %d, %Y at %I:%M %p")}
              </p>
            </div>
            <div>
              <h4 class="text-sm font-medium text-base-content/70">Slug</h4>
              <div class="flex items-center space-x-2 mt-1">
                <code class="bg-base-200 px-2 py-1 rounded text-sm">
                  /blog/{@selected_post.slug}
                </code>
                <%= if @selected_post.published == :published and @selected_post.slug do %>
                  <.link
                    href={~p"/blog/#{@selected_post.slug}"}
                    target="_blank"
                    class="text-primary hover:text-primary-focus"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                  </.link>
                <% end %>
              </div>
            </div>
          </div>

          <div class="pt-6 border-t">
            <%= if @delete_confirmation do %>
              <div class="flex w-full justify-between space-x-4">
                <button class="btn btn-error w-full" phx-click="confirm_delete_post">
                  Confirm Delete
                </button>
                <button class="btn w-full" phx-click="cancel_delete">
                  Cancel
                </button>
              </div>
            <% else %>
              <button class="btn btn-error w-full" phx-click="delete_post">
                Delete Post
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <input type="radio" name="post_tabs_#{@context}" role="tab" class="tab" aria-label="Activity" />
      <div role="tabpanel" class="tab-content bg-base-100 border-base-300 rounded-box p-6">
        <%= if @selected_post do %>
          <.live_component
            module={ActivityTimelineComponent}
            id={"activity-timeline-post-#{@selected_post.id}-#{@context}"}
            activities={@post_activities}
            show_timestamps={true}
            timestamps={
              %{
                inserted_at: @selected_post.inserted_at,
                updated_at: @selected_post.updated_at
              }
            }
          />
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:created, %{type: :blog_post, post: _post}}, socket) do
    # Reload the entire posts list to ensure consistency
    socket = load_posts(socket, socket.assigns.page)
    {:noreply, socket}
  end

  def handle_info({:updated, %{type: :blog_post, post: updated_post}}, socket) do
    # Reload the entire posts list to ensure consistency
    socket = load_posts(socket, socket.assigns.page)

    # If this is the currently selected post, update it and reload activities
    socket =
      if socket.assigns.selected_post && socket.assigns.selected_post.id == updated_post.id do
        activities = Core.Tracking.get_blog_post_activities(updated_post.id, 20)
        changeset = Blog.change_post(updated_post)

        socket
        |> assign(:selected_post, updated_post)
        |> assign(:changeset, changeset)
        |> assign(:post_activities, activities)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:deleted, %{type: :blog_post, id: post_id}}, socket) do
    # If this was the selected post, clear the selection
    socket =
      if socket.assigns.selected_post && socket.assigns.selected_post.id == post_id do
        socket
        |> assign(:selected_post, nil)
        |> assign(:changeset, nil)
        |> assign(:post_activities, [])
      else
        socket
      end

    # Reload the entire posts list to ensure consistency
    socket = load_posts(socket, socket.assigns.page)

    {:noreply, socket}
  end
end
