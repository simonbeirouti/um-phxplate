defmodule Admin.PageMeta do
  @moduledoc """
  Helper functions for managing page metadata like titles, descriptions, and other meta tags.
  """

  @doc """
  Assigns common page metadata to a socket or connection.

  ## Options
    * `:title` - The page title (required)
    * `:description` - The page description (optional)
    * `:image` - The page image URL (optional)
    * `:url` - The page URL (optional)
  """
  def assign_metadata(conn_or_socket, opts \\ []) do
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description)
    image = Keyword.get(opts, :image, "https://via.placeholder.com/1200x630")
    base_url = Admin.config(:base_url)
    url = base_url <> Keyword.get(opts, :url, "")

    metadata = %{
      page_title: "#{Admin.config(:title)} | #{title}",
      page_description: description,
      page_image: image,
      page_url: url
    }

    case conn_or_socket do
      %Plug.Conn{} = conn ->
        Enum.reduce(metadata, conn, fn {key, value}, conn ->
          Plug.Conn.assign(conn, key, value)
        end)
      socket ->
        Phoenix.Component.assign(socket, metadata)
    end
  end
end
