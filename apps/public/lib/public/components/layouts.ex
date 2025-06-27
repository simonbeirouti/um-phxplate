defmodule Public.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is rendered as component
  in regular views and live views.
  """
  use Public, :html

  embed_templates "layouts/*"

  @doc """
  Renders the app layout

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layout.app>

  """
  # attr :flash, :map, required: true, doc: "the map of flash messages"

  # attr :current_scope, :map,
  #   default: nil,
  #   doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  # slot :inner_block, required: true

  # def app(assigns) do
  #   ~H"""
  #   <header class="navbar px-4 sm:px-6 lg:px-8">
  #     <div class="flex-1">
  #       <a href="/" class="flex-1 flex w-fit items-center gap-2">
  #         <img src={~p"/images/logo.svg"} width="36" />
  #         <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
  #       </a>
  #     </div>
  #     <div class="flex-none">
  #       <ul class="flex flex-column px-1 space-x-4 items-center">
  #         <li>
  #           <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
  #         </li>
  #         <li>
  #           <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
  #         </li>
  #         <li>
  #           <.theme_toggle />
  #         </li>
  #         <li>
  #           <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
  #             Get Started <span aria-hidden="true">&rarr;</span>
  #           </a>
  #         </li>
  #       </ul>
  #     </div>
  #   </header>

  #   <main class="px-4 py-20 sm:px-6 lg:px-8">
  #     <div class="mx-auto max-w-2xl space-y-4">
  #       {render_slot(@inner_block)}
  #     </div>
  #   </main>

  #   <.flash_group flash={@flash} />
  #   """
  # end

  def auth(assigns) do
    current_path =
      case assigns do
        %{socket: %{private: %{connect_params: %{"_mounts" => 0}}}} ->
          assigns.socket.private.connect_params["request_path"]

        %{conn: conn} ->
          conn.request_path

        _ ->
          "/"
      end

    assigns = Map.put_new(assigns, :current_path, current_path)

    ~H"""
    <div class="flex flex-col lg:flex-row h-[calc(100vh-4.3rem)]">
      <div class="w-full lg:w-1/2 p-4">
        {@inner_content}
      </div>
      <div
        class="w-full lg:w-1/2 bg-cover bg-center"
        style="background-image: url('/images/coffee.jpg')"
      >
      </div>
    </div>
    """
  end

  def public(assigns) do
    ~H"""
    <div class="min-h-[calc(100vh-4rem)]">
      <main>
        {@inner_content}
      </main>
    </div>
    """
  end
end
