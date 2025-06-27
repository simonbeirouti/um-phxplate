defmodule Public.Components.ModalComponent do
  use Public, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@show}>
        <div
          id={@id}
          class="modal modal-open"
          phx-window-keydown="close"
          phx-key="escape"
          phx-target={@id}
        >
          <div class="modal-box">
            <form phx-submit="close">
              <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2">✕</button>
            </form>
            <h3 class="font-bold text-lg"><%= @title %></h3>
            <div class="py-4">
              <%= render_slot(@inner_block) %>
            </div>
          </div>
          <form phx-submit="close" class="modal-backdrop">
            <button type="submit">close</button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("close", _, socket) do
    send(self(), {:close_modal, socket.assigns.id})
    {:noreply, socket}
  end
end
