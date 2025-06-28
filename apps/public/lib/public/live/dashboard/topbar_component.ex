defmodule Public.Dashboard.TopbarComponent do
  use Public, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 text-base-content">
      <div
        role="navigation"
        aria-label="Navbar"
        class="flex items-center justify-between px-3"
        id="layout-topbar"
      >
        <div class="inline-flex items-center gap-3">
          <label
            class="btn btn-square btn-ghost btn-md"
            aria-label="Leftmenu toggle"
            for="layout-sidebar-toggle-trigger"
          >
            <.icon name="hero-bars-3" class="size-6" />
          </label>
          <button
            phx-click={JS.dispatch("show", to: "#topbar-search-modal")}
            class="btn btn-outline btn-sm btn-ghost border-base-300 text-base-content/70 hidden h-9 w-48 justify-start gap-2 !text-sm md:flex"
          >
            <.icon name="hero-magnifying-glass" class="size-4" />
            <span>Search</span>
          </button>
          <button
            phx-click={JS.dispatch("show", to: "#topbar-search-modal")}
            class="btn btn-outline btn-sm btn-square btn-ghost border-base-300 text-base-content/70 flex size-9 md:hidden"
            aria-label="Search"
          >
            <.icon name="hero-magnifying-glass" class="size-4" />
          </button>
        </div>
        <div class="inline-flex items-center gap-1.5">
          <.theme_toggle />
          <%!-- <label for="layout-rightbar-drawer" class="btn btn-circle btn-ghost btn-sm drawer-button">
            <.icon name="hero-cog-6-tooth" class="size-4.5" />
          </label> --%>
          <%!-- <div class="dropdown dropdown-bottom sm:dropdown-end max-sm:dropdown-center">
            <div
              tabindex="0"
              role="button"
              class="btn btn-circle btn-ghost btn-sm"
              aria-label="Notifications"
            >
              <.icon name="hero-bell" class="size-4.5" />
            </div>
            <div
              tabindex="0"
              class="dropdown-content bg-base-100 rounded-box card card-compact mt-5 w-60 p-2 shadow sm:w-84"
            >
              <div class="flex items-center justify-between px-2">
                <p class="text-base font-medium">Notification</p>
                <button tabindex="0" class="btn btn-sm btn-circle btn-ghost" aria-label="Close">
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
              <div class="flex items-center justify-center">
                <div class="badge badge-sm badge-primary badge-soft">Today</div>
              </div>
              <div class="mt-2">
                <div class="rounded-box hover:bg-base-200 flex cursor-pointer gap-3 px-2 py-1.5 transition-all">
                  <img
                    class="bg-base-200 mask mask-squircle size-10 p-0.5"
                    alt=""
                    src="/images/avatars/4.png"
                  />
                  <div class="grow">
                    <p class="text-sm leading-tight">
                      Customer has requested a return for item
                    </p>
                    <p class="text-base-content/60 text-end text-xs leading-tight">
                      1 Hour ago
                    </p>
                  </div>
                </div>
                <div class="rounded-box hover:bg-base-200 flex cursor-pointer gap-3 px-2 py-1.5 transition-all">
                  <img
                    class="bg-base-200 mask mask-squircle size-10 p-0.5"
                    alt=""
                    src="/images/avatars/5.png"
                  />
                  <div class="grow">
                    <p class="text-sm leading-tight">
                      A new review has been submitted for product
                    </p>
                    <p class="text-base-content/60 text-end text-xs leading-tight">
                      1 Hour ago
                    </p>
                  </div>
                </div>
              </div>
              <div class="mt-2 flex items-center justify-center">
                <div class="badge badge-sm">Previous</div>
              </div>
              <div class="mt-2">
                <div class="rounded-box hover:bg-base-200 flex cursor-pointer gap-3 px-2 py-1.5 transition-all">
                  <img
                    class="bg-base-200 mask mask-squircle size-10 p-0.5"
                    alt=""
                    src="/images/avatars/1.png"
                  />
                  <div class="grow">
                    <p class="text-sm leading-tight">
                      Prepare for the upcoming weekend promotion
                    </p>
                    <p class="text-base-content/60 text-end text-xs leading-tight">
                      2 Days ago
                    </p>
                  </div>
                </div>
                <div class="rounded-box hover:bg-base-200 flex cursor-pointer gap-3 px-2 py-1.5 transition-all">
                  <img
                    class="bg-base-200 mask mask-squircle size-10 p-0.5"
                    alt=""
                    src="/images/avatars/2.png"
                  />
                  <div class="grow">
                    <p class="text-sm leading-tight">
                      Product 'ABC123' is running low in stock.
                    </p>
                    <p class="text-base-content/60 text-end text-xs leading-tight">
                      3 Days ago
                    </p>
                  </div>
                </div>
                <div class="rounded-box hover:bg-base-200 flex cursor-pointer gap-3 px-2 py-1.5 transition-all">
                  <img
                    class="bg-base-200 mask mask-squircle size-10 p-0.5"
                    alt=""
                    src="/images/avatars/3.png"
                  />
                  <div class="grow">
                    <p class="text-sm leading-tight">
                      Payment received for Order ID: #67890
                    </p>
                    <p class="text-base-content/60 text-end text-xs leading-tight">
                      Week ago
                    </p>
                  </div>
                </div>
              </div>
              <hr class="border-base-300 -mx-2 mt-2" />
              <div class="flex items-center justify-between pt-2">
                <button class="btn btn-sm btn-ghost">Mark as read</button>
                <button class="btn btn-sm btn-soft btn-primary">View All</button>
              </div>
            </div>
          </div> --%>
          <%!-- <div class="dropdown dropdown-bottom dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost rounded-btn px-1.5">
              <div class="flex items-center gap-2">
                <div class="avatar">
                  <div class="bg-base-200 mask mask-squircle w-8">
                    <img
                      alt="Avatar"
                      src={@dashboard_user.profile.avatar_url || "/images/avatars/1.png"}
                    />
                  </div>
                </div>
                <div class="-space-y-0.5 text-start">
                  <p class="text-sm"><%= @dashboard_user.profile.first_name %></p>
                  <p class="text-base-content/60 text-xs">Profile</p>
                </div>
              </div>
            </div>
            <div class="dropdown-content bg-base-100 rounded-box mt-4 w-44 shadow" tabindex="0">
              <ul class="menu w-full p-2">
                <li>
                  <a href="/pages-settings.html">
                    <.icon name="hero-user" class="size-4" />
                    <span>My Profile</span>
                  </a>
                </li>
                <li>
                  <a href="/pages-settings.html">
                    <.icon name="hero-cog-6-tooth" class="size-4" />
                    <span>Settings</span>
                  </a>
                </li>
                <li>
                  <a href="/pages-get-help.html">
                    <.icon name="hero-question-mark-circle" class="size-4" />
                    <span>Help</span>
                  </a>
                </li>
              </ul>
              <hr class="border-base-300" />
              <ul class="menu w-full p-2">
                <li>
                  <div>
                    <.icon name="hero-arrows-right-left" class="size-4" />
                    <span>Switch Account</span>
                  </div>
                </li>
                <li>
                  <a class="text-error hover:bg-error/10" href={~p"/logout"}>
                    <.icon name="hero-arrow-left-on-rectangle" class="size-4" />
                    <span>Logout</span>
                  </a>
                </li>
              </ul>
            </div>
          </div> --%>
        </div>
      </div>
    </div>
    """
  end
end
