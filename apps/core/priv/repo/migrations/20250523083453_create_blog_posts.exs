defmodule Core.Repo.Migrations.CreateBlogPosts do
  use Ecto.Migration

  def change do
    create table(:blog_posts) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :string
      add :content, :text, null: false
      add :meta, :map, default: "{}"
      add :published, :string, default: "draft", null: false

      timestamps()
    end

    create index(:blog_posts, [:published])
    create unique_index(:blog_posts, [:slug])
  end
end
