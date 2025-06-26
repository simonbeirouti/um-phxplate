defmodule Public.PageController do
  @moduledoc """
  Controller for handling static public pages.

  This controller is responsible for rendering the public-facing pages of the application
  such as the home page and about page. It assigns appropriate metadata for SEO purposes
  to each page.
  """
  use Public, :controller
  alias Public.PageMeta

  @doc """
  Renders the home page.

  Assigns metadata for SEO purposes and renders the home template without a layout.
  """
  def home(conn, _params) do
    conn
    |> PageMeta.assign_metadata(
      title: "Home",
      description: "Welcome to Phxplate",
      url: "/"
    )
    |> render(:home, layout: false)
  end

  @doc """
  Renders the about page.

  Assigns metadata for SEO purposes and renders the about template without a layout.
  """
  def about(conn, _params) do
    conn
    |> PageMeta.assign_metadata(
      title: "About",
      description: "Learn more about Phxplate",
      url: "/about"
    )
    |> render(:about, layout: false)
  end
end
