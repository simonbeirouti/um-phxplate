defmodule Public.BlogLive do
  @moduledoc """
  Public LiveView for displaying published blog posts.

  This view shows a paginated list of published blog posts that can be viewed
  by anyone without authentication. Each post shows the title, description,
  publication date, and a link to read the full post.
  """
  use Public, :live_view
  alias Core.Blog
  alias Public.PageMeta
  alias Core.PubSub.DataSync
  alias Public.Components.Markdown

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("blog_posts", "all")
    end

    {:ok, load_posts(socket, 1)}
  end

  defp load_posts(socket, page) do
    per_page = 10

    posts = Blog.list_published_posts(page: page, per_page: per_page)
    total_posts = Blog.count_published_posts()
    total_pages = max(1, ceil(total_posts / per_page))

    socket
    |> assign(:posts, posts)
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:per_page, per_page)
    |> PageMeta.assign_metadata(
      title: "Blog",
      description: "Read our latest blog posts and articles",
      url: "/blog"
    )
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    {:noreply, load_posts(socket, page)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page =
      case params["page"] do
        nil -> 1
        page_param -> String.to_integer(page_param)
      end

    {:noreply, load_posts(socket, page)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header_section title="Blog" subtitle="Read our latest posts and insights" />
    <div class="max-w-7xl mx-auto px-4 py-8 min-h-[400px]">
      <%= if Enum.empty?(@posts) do %>
        <div class="text-center py-12">
          <div class="max-w-md mx-auto">
            <.icon name="hero-document-text" class="mx-auto h-12 w-12 text-base-content/40" />
            <h3 class="mt-2 text-sm font-medium text-base-content">No posts yet</h3>
            <p class="mt-1 text-sm text-base-content/60">Check back soon for new content!</p>
          </div>
        </div>
      <% else %>
        <div class="gap-6 grid grid-cols-1 sm:grid-cols-2">
          <%= for post <- @posts do %>
            <.link href={~p"/blog/#{post.slug}"} class="block">
              <article class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow duration-200">
                <div class="card-body">
                  <div class="flex flex-col md:flex-row items-start justify-between mb-4 gap-2">
                    <h2 class="card-title text-xl text-base-content"><%= post.title %></h2>
                    <time class="text-sm text-base-content/60 whitespace-nowrap">
                      <%= format_date(post.inserted_at) %>
                    </time>
                  </div>

                  <p class="text-base-content/70 mb-4 leading-relaxed">
                    <%= post.description || Markdown.excerpt(post.content, 200) %>
                  </p>

                  <div class="card-actions justify-end">
                    Read more <.icon name="hero-arrow-right" class="ml-2 h-4 w-4" />
                  </div>
                </div>
              </article>
            </.link>
          <% end %>
        </div>

        <%= if @total_pages > 1 do %>
          <div class="mt-12 flex justify-center">
            <div class="join">
              <%= if @page > 1 do %>
                <button class="join-item btn" phx-click="paginate" phx-value-page={@page - 1}>
                  <.icon name="hero-arrow-left" class="w-4 h-4" />
                </button>
              <% end %>

              <%= for page_num <- max(1, @page - 2)..min(@total_pages, @page + 2) do %>
                <button
                  class={["join-item btn", if(page_num == @page, do: "btn-active", else: "")]}
                  phx-click="paginate"
                  phx-value-page={page_num}
                >
                  <%= page_num %>
                </button>
              <% end %>

              <%= if @page < @total_pages do %>
                <button class="join-item btn" phx-click="paginate" phx-value-page={@page + 1}>
                  <.icon name="hero-arrow-right" class="w-4 h-4" />
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    <.cta />
    """
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  @impl true
  def handle_info({:created, %{type: :blog_post, post: _post}}, socket) do
    socket = load_posts(socket, socket.assigns.page)
    {:noreply, socket}
  end

  def handle_info({:updated, %{type: :blog_post, post: _updated_post}}, socket) do
    socket = load_posts(socket, socket.assigns.page)
    {:noreply, socket}
  end

  def handle_info({:deleted, %{type: :blog_post, id: _post_id}}, socket) do
    socket = load_posts(socket, socket.assigns.page)
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end
