defmodule Public.BlogShowLive do
  @moduledoc """
  Public LiveView for displaying individual published blog posts.

  This view shows the full content of a published blog post accessed by its slug.
  It includes proper meta tags for SEO and social sharing.
  """
  use Public, :live_view
  alias Public.Blog
  alias Public.PageMeta
  alias Core.PubSub.DataSync
  alias Public.Components.Markdown

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    if connected?(socket) do
      DataSync.subscribe("blog_posts", "all")
    end

    case Blog.get_published_post_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Blog post not found")
         |> redirect(to: ~p"/blog")}

      post ->
        if connected?(socket) do
          DataSync.subscribe("blog_posts", post.id)
        end

        socket =
          socket
          |> assign(:post, post)
          |> PageMeta.assign_metadata(
            title: post.title,
            description: post.description || Markdown.excerpt(post.content, 160),
            url: "/blog/#{post.slug}"
          )

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Blog.get_published_post_by_slug(slug) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Blog post not found")
         |> redirect(to: ~p"/blog")}

      post ->
        socket =
          socket
          |> assign(:post, post)
          |> PageMeta.assign_metadata(
            title: post.title,
            description: post.description || Markdown.excerpt(post.content, 160),
            url: "/blog/#{post.slug}"
          )

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header_section title={@post.title} subtitle={@post.description} date={@post.inserted_at} />
    <div class="max-w-7xl mx-auto px-4 py-12">
      <article>
        <div class="prose prose-lg max-w-none">
          <%= Markdown.to_html(@post.content) %>
        </div>
      </article>

      <div class="mt-8 text-center">
        <.link
          href={~p"/blog"}
          class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
        >
          <.icon name="hero-arrow-left" class="mr-2 h-4 w-4" /> Back to Blog
        </.link>
      </div>
    </div>
    <.cta />
    """
  end

  @impl true
  def handle_info({:updated, %{type: :blog_post, post: updated_post}}, socket) do
    # Check if this is our post and if it's still published
    if socket.assigns.post.id == updated_post.id do
      if updated_post.published == :published do
        # Update the post content
        socket =
          socket
          |> assign(:post, updated_post)
          |> PageMeta.assign_metadata(
            title: updated_post.title,
            description: updated_post.description || Markdown.excerpt(updated_post.content, 160),
            url: "/blog/#{updated_post.slug}"
          )

        {:noreply, socket}
      else
        # Post is no longer published, redirect to blog listing
        {:noreply,
         socket
         |> put_flash(:info, "This post is no longer available")
         |> redirect(to: ~p"/blog")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted, %{type: :blog_post, id: post_id}}, socket) do
    # If our post was deleted, redirect to blog listing
    if socket.assigns.post.id == post_id do
      {:noreply,
       socket
       |> put_flash(:info, "This post has been removed")
       |> redirect(to: ~p"/blog")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:created, %{type: :blog_post, post: _post}}, socket) do
    # Don't need to do anything for new posts on individual post pages
    {:noreply, socket}
  end
end
