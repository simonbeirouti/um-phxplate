defmodule Core.Blog do
  @moduledoc """
  The Blog context.

  This module provides functions for managing blog posts, with authorization
  checks to ensure only super admin users can create, update, or delete posts.
  """

  import Ecto.Query

  alias Core.Repo
  alias Core.Blog.Post
  alias Core.Accounts.User
  alias Core.Tracking
  alias Core.PubSub.DataSync

  @doc """
  Returns a paginated list of blog posts.

  ## Options

    * `:page` - The page number (defaults to 1)
    * `:per_page` - The number of posts per page (defaults to 10)
    * `:published_only` - When true, only returns published posts (defaults to false)

  ## Examples

      iex> list_posts()
      [%Post{}, ...]

      iex> list_posts(page: 2, per_page: 5)
      [%Post{}, ...]

      iex> list_posts(published_only: true)
      [%Post{published: :published}, ...]
  """
  def list_posts(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)
    published_only = Keyword.get(opts, :published_only, false)

    offset = (page - 1) * per_page

    query = from(p in Post, order_by: [desc: p.inserted_at])

    query =
      if published_only do
        from(p in query, where: p.published == :published)
      else
        query
      end

    Repo.all(
      from p in query,
        limit: ^per_page,
        offset: ^offset
    )
  end

  @doc """
  Gets a single post.

  Raises `Ecto.NoResultsError` if the Post does not exist.

  ## Examples

      iex> get_post!(123)
      %Post{}

      iex> get_post!(456)
      ** (Ecto.NoResultsError)
  """
  def get_post!(id), do: Repo.get!(Post, id)

  @doc """
  Gets a single post by ID, returning nil if not found.

  ## Examples

      iex> get_post(123)
      %Post{}

      iex> get_post(456)
      nil
  """
  def get_post(id), do: Repo.get(Post, id)

  @doc """
  Gets a single post by slug.

  Raises `Ecto.NoResultsError` if the Post does not exist.

  ## Examples

      iex> get_post_by_slug!("my-blog-post")
      %Post{}

      iex> get_post_by_slug!("non-existent")
      ** (Ecto.NoResultsError)
  """
  def get_post_by_slug!(slug), do: Repo.get_by!(Post, slug: slug)

  @doc """
  Gets a single post by slug, returning nil if not found.

  ## Examples

      iex> get_post_by_slug("my-blog-post")
      %Post{}

      iex> get_post_by_slug("non-existent")
      nil
  """
  def get_post_by_slug(slug), do: Repo.get_by(Post, slug: slug)

  @doc """
  Gets a published post by slug, returning nil if not found or not published.

  ## Examples

      iex> get_published_post_by_slug("my-blog-post")
      %Post{published: :published}

      iex> get_published_post_by_slug("draft-post")
      nil
  """
  def get_published_post_by_slug(slug) do
    Repo.get_by(Post, slug: slug, published: :published)
  end

  @doc """
  Counts the total number of blog posts.

  ## Options

    * `:published_only` - When true, only counts published posts

  ## Examples

      iex> count_posts()
      10

      iex> count_posts(published_only: true)
      5
  """
  def count_posts(opts \\ []) do
    published_only = Keyword.get(opts, :published_only, false)

    query = if published_only do
      from(p in Post, where: p.published == :published)
    else
      from(p in Post)
    end

    Repo.aggregate(query, :count, :id)
  end

  @doc """
  Creates a post.

  Requires a super_admin user to create the post.

  ## Examples

      iex> create_post(%{field: value}, %User{role: :super_admin})
      {:ok, %Post{}}

      iex> create_post(%{field: bad_value}, %User{role: :super_admin})
      {:error, %Ecto.Changeset{}}

      iex> create_post(%{field: value}, %User{role: :admin})
      {:error, :unauthorized}
  """
  def create_post(attrs \\ %{}, user)

  def create_post(attrs, %User{role: :super_admin} = user) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        Tracking.track_blog_activity("post_create", post, user, %{}, %{
          title: post.title,
          slug: post.slug
        })

        # Broadcast the created post (both to specific post and all)
        IO.puts("🚀 BLOG: Broadcasting created post: #{post.id}")
        DataSync.broadcast("blog_posts", post.id, {:created, %{type: :blog_post, post: post}})
        DataSync.broadcast("blog_posts", "all", {:created, %{type: :blog_post, post: post}})
        {:ok, post}
      error -> error
    end
  end

  def create_post(_attrs, _user), do: {:error, :unauthorized}

  @doc """
  Updates a post.

  Requires a super_admin user to update the post.

  ## Examples

      iex> update_post(post, %{field: new_value}, %User{role: :super_admin})
      {:ok, %Post{}}

      iex> update_post(post, %{field: bad_value}, %User{role: :super_admin})
      {:error, %Ecto.Changeset{}}

      iex> update_post(post, %{field: value}, %User{role: :admin})
      {:error, :unauthorized}
  """
  def update_post(%Post{} = post, attrs, %User{role: :super_admin} = user) do
    # Get the post before changes for comparison
    original_post = %{
      title: post.title,
      slug: post.slug,
      description: post.description,
      content: post.content,
      published: post.published
    }

    post
    |> Post.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_post} ->
        # Calculate what changed
        changes = %{}
        |> maybe_add_change(original_post.title != updated_post.title, :title, original_post.title, updated_post.title)
        |> maybe_add_change(original_post.slug != updated_post.slug, :slug, original_post.slug, updated_post.slug)
        |> maybe_add_change(original_post.description != updated_post.description, :description, original_post.description, updated_post.description)
        |> maybe_add_change(original_post.published != updated_post.published, :published, original_post.published, updated_post.published)
        |> maybe_add_content_change(original_post.content, updated_post.content)

        Tracking.track_blog_activity("post_update", updated_post, user, changes, %{
          title: updated_post.title,
          slug: updated_post.slug
        })

        # Broadcast the updated post (both to specific post and all)
        IO.puts("🚀 BLOG: Broadcasting updated post: #{updated_post.id}")
        DataSync.broadcast("blog_posts", updated_post.id, {:updated, %{type: :blog_post, post: updated_post}})
        DataSync.broadcast("blog_posts", "all", {:updated, %{type: :blog_post, post: updated_post}})
        {:ok, updated_post}
      error -> error
    end
  end

  def update_post(_post, _attrs, _user), do: {:error, :unauthorized}

  @doc """
  Deletes a post.

  Requires a super_admin user to delete the post.

  ## Examples

      iex> delete_post(post, %User{role: :super_admin})
      {:ok, %Post{}}

      iex> delete_post(post, %User{role: :admin})
      {:error, :unauthorized}
  """
  def delete_post(%Post{} = post, %User{role: :super_admin} = user) do
    post_details = %{
      id: post.id,
      title: post.title,
      slug: post.slug
    }

    Repo.delete(post)
    |> case do
      {:ok, _deleted_post} ->
        Tracking.track_blog_activity("post_delete", %{id: post_details.id}, user, %{}, post_details)

        # Broadcast the deleted post (both to specific post and all)
        IO.puts("🚀 BLOG: Broadcasting deleted post: #{post_details.id}")
        DataSync.broadcast("blog_posts", post_details.id, {:deleted, %{type: :blog_post, id: post_details.id}})
        DataSync.broadcast("blog_posts", "all", {:deleted, %{type: :blog_post, id: post_details.id}})
        {:ok, post}
      error -> error
    end
  end

  def delete_post(_post, _user), do: {:error, :unauthorized}

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post changes.

  ## Examples

      iex> change_post(post)
      %Ecto.Changeset{data: %Post{}}
  """
  def change_post(%Post{} = post, attrs \\ %{}) do
    Post.changeset(post, attrs)
  end

  @doc """
  Returns a list of published blog posts for public viewing.

  ## Options

    * `:page` - The page number (defaults to 1)
    * `:per_page` - The number of posts per page (defaults to 10)

  ## Examples

      iex> list_published_posts()
      [%Post{published: :published}, ...]

      iex> list_published_posts(page: 2, per_page: 5)
      [%Post{published: :published}, ...]
  """
  def list_published_posts(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)

    offset = (page - 1) * per_page

    from(p in Post,
      where: p.published == :published,
      order_by: [desc: p.inserted_at],
      limit: ^per_page,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Counts the total number of published blog posts.

  ## Examples

      iex> count_published_posts()
      5
  """
  def count_published_posts do
    from(p in Post, where: p.published == :published)
    |> Repo.aggregate(:count, :id)
  end

  # Helper functions for tracking changes
  defp maybe_add_change(changes, false, _field, _old_value, _new_value), do: changes
  defp maybe_add_change(changes, true, field, old_value, new_value) do
    Map.put(changes, field, %{from: old_value, to: new_value})
  end

  defp maybe_add_content_change(changes, old_content, new_content) do
    if old_content != new_content do
      content_excerpt_length = 100
      old_excerpt = String.slice(old_content || "", 0, content_excerpt_length)
      new_excerpt = String.slice(new_content || "", 0, content_excerpt_length)

      changes
      |> Map.put(:content_changed, true)
      |> Map.put(:content_excerpt, %{
        from: old_excerpt <> (if String.length(old_content || "") > content_excerpt_length, do: "...", else: ""),
        to: new_excerpt <> (if String.length(new_content || "") > content_excerpt_length, do: "...", else: "")
      })
    else
      changes
    end
  end
end
