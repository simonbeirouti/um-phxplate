defmodule Core.Blog.Post do
  @moduledoc """
  Schema for blog posts.

  This module defines the database schema for blog posts with fields for title,
  description, content, metadata, publication status, slug for SEO-friendly URLs, and timestamps.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @publish_statuses [:published, :draft, :unpublished]

  schema "blog_posts" do
    field :title, :string
    field :slug, :string
    field :description, :string
    field :content, :string
    field :meta, :map, default: %{}
    field :published, Ecto.Enum, values: @publish_statuses, default: :draft

    timestamps()
  end

  @doc """
  Creates a changeset for a blog post.
  """
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :slug, :description, :content, :meta, :published])
    |> validate_required([:title, :content])
    |> validate_length(:title, min: 3, max: 255)
    |> validate_length(:description, max: 500)
    |> maybe_generate_slug()
    |> validate_required([:slug])
    |> validate_length(:slug, min: 3, max: 255)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "must contain only lowercase letters, numbers, and hyphens")
    |> unique_constraint(:slug)
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        case get_field(changeset, :title) do
          nil -> changeset
          title -> put_change(changeset, :slug, generate_slug(title))
        end
      "" ->
        case get_field(changeset, :title) do
          nil -> changeset
          title -> put_change(changeset, :slug, generate_slug(title))
        end
      _slug -> changeset
    end
  end

  defp generate_slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
