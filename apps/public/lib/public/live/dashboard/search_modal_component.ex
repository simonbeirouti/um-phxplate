defmodule Public.Dashboard.SearchModalComponent do
  use Public, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <dialog id="topbar-search-modal" class="modal p-0" phx-hook="Modal">
      <div class="modal-box p-0">
        <div class="input border-base-300 w-full rounded-none border-0 border-b focus:!outline-0 active:!outline-0">
          <.icon name="hero-magnifying-glass" class="text-base-content/60 size-4.5" />
          <input class="grow" placeholder="Search" aria-label="Search" type="search" />
          <form method="dialog">
            <button class="btn btn-sm btn-circle btn-ghost" aria-label="Close">
              <.icon name="hero-x-mark" class="text-base-content/80 size-4" />
            </button>
          </form>
        </div>
        <ul class="menu w-full pt-0">
          <li class="menu-title">Actions</li>
          <li>
            <div>
              <.icon name="hero-folder-plus" class="size-4.5" />
              <p class="grow text-sm">Create a new folder</p>
            </div>
          </li>
          <li>
            <div>
              <.icon name="hero-document-plus" class="size-4.5" />
              <p class="grow text-sm">Upload new document</p>
            </div>
          </li>
          <li>
            <div>
              <.icon name="hero-user-plus" class="size-4.5" />
              <p class="grow text-sm">Invite to project</p>
            </div>
          </li>
        </ul>
        <hr class="border-base-300 h-px" />
        <ul class="menu w-full pt-0">
          <li class="menu-title">Quick Links</li>
          <li>
            <div>
              <.icon name="hero-folder" class="size-4.5" />
              <p class="grow text-sm">File Manager</p>
            </div>
          </li>
          <li>
            <div>
              <.icon name="hero-user" class="size-4.5" />
              <p class="grow text-sm">Profile</p>
            </div>
          </li>
          <li>
            <div>
              <.icon name="hero-computer-desktop" class="size-4.5" />
              <p class="grow text-sm">Dashboard</p>
            </div>
          </li>
          <li>
            <div>
              <.icon name="hero-question-mark-circle" class="size-4.5" />
              <p class="grow text-sm">Support</p>
            </div>
          </li>
          <li>
            <div>
              <.icon name="hero-command-line" class="size-4.5" />
              <p class="grow text-sm">Keyboard Shortcuts</p>
            </div>
          </li>
        </ul>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end
end
