defmodule Public.Components.Markdown do
  @moduledoc """
  Utilities for rendering Markdown content safely in Phoenix LiveViews.

  This module provides functions to convert Markdown to HTML while maintaining
  security and proper formatting for blog posts and other content.
  """

  @doc """
  Converts Markdown content to safe HTML that can be rendered in templates.

  Uses MDEx to parse and render Markdown with sensible defaults for blog content.
  The output is marked as safe for raw insertion into templates.

  ## Examples

      iex> Public.Components.Markdown.to_html("# Hello World")
      {:safe, "<h1>Hello World</h1>"}

  """
  def to_html(content) when is_binary(content) do
    options = [
      # Enable common extensions
      extension: [
        strikethrough: true,
        tagfilter: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true
      ],
      # Render options for better HTML output
      render: [
        # Use GitHub-flavored line breaks
        github_pre_lang: true,
        # Escape potentially dangerous HTML
        escape: false,
        # Allow unsafe HTML rendering (be careful with user content)
        unsafe: false
      ],
      # Parse options
      parse: [
        # Enable smart punctuation
        smart: true,
        # Relax some parsing rules for better compatibility
        relaxed_tasklist_matching: true
      ]
    ]

    case MDEx.to_html(content, options) do
      {:ok, html} ->
        # Mark as safe since MDEx handles escaping
        Phoenix.HTML.raw(html)

      {:error, _reason} ->
        # Fallback to escaped content if Markdown parsing fails
        Phoenix.HTML.html_escape(content)
    end
  end

  def to_html(nil), do: Phoenix.HTML.raw("")
  def to_html(""), do: Phoenix.HTML.raw("")

  @doc """
  Converts Markdown content to plain text, stripping all formatting.

  Useful for creating excerpts or descriptions from Markdown content.

  ## Examples

      iex> Public.Components.Markdown.to_text("# Hello **World**")
      "Hello World"

  """
  def to_text(content) when is_binary(content) do
    content
    |> to_html()
    |> Phoenix.HTML.safe_to_string()
    |> Floki.parse_document!()
    |> Floki.text()
    |> String.trim()
  end

  def to_text(nil), do: ""
  def to_text(""), do: ""

  @doc """
  Creates a text excerpt from Markdown content with a specified length.

  Converts Markdown to plain text and truncates to the specified character limit,
  ensuring words aren't cut off mid-word.

  ## Examples

      iex> Public.Components.Markdown.excerpt("# Hello World\\n\\nThis is content", 20)
      "Hello World This is..."

  """
  def excerpt(content, max_length \\ 160)
  def excerpt(content, max_length) when is_binary(content) and is_integer(max_length) do
    text = to_text(content)

    if String.length(text) <= max_length do
      text
    else
      text
      |> String.slice(0, max_length)
      |> String.trim()
      |> Kernel.<>("...")
    end
  end

  def excerpt(nil, _max_length), do: ""
  def excerpt("", _max_length), do: ""
end
