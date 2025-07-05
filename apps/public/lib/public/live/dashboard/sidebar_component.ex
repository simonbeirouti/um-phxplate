defmodule Public.Dashboard.SidebarComponent do
  use Public, :live_component

  alias Public.Live.Hooks.LayoutHooks

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
      <input
        type="checkbox"
        id="layout-sidebar-toggle-trigger"
        class="hidden"
        aria-label="Toggle layout sidebar"
        phx-hook="Sidebar"
      />

      <div id="layout-sidebar" class="flex flex-col h-full">
        <!-- User info at top -->
        <div class="flex min-h-16 items-center gap-2.5 px-3 py-2">
          <div class="avatar">
            <div class="bg-base-200 mask mask-squircle w-8">
              <img
                alt="Avatar"
                src={@dashboard_user.profile.avatar_url || "/images/avatars/1.png"}
              />
            </div>
          </div>
          <div class="grow -space-y-0.5">
            <p class="text-sm font-medium">
              {@dashboard_user.profile.first_name} {@dashboard_user.profile.last_name}
            </p>
            <p class="text-base-content/60 text-xs">{@dashboard_user.email}</p>
          </div>
        </div>
        <div class="relative min-h-0 grow">
          <div data-simplebar class="size-full">
            <div id="sidebar-menu" class="menu">
              <%= for group <- @dashboard_nav do %>
                <p class="sidebar-menu-title">{group.title}</p>
                <%= for item <- group.items do %>
                  <.link
                    navigate={item.path}
                    class={
                      "sidebar-menu-item flex items-center gap-2 #{if LayoutHooks.nav_item_active?(item, @current_path), do: "active"}"
                    }
                  >
                    <.icon name={item.icon} class="size-4" />
                    <span class="grow">{item.label}</span>
                  </.link>
                <% end %>
              <% end %>
              <!--
              <div class="group collapse">
                <input
                  aria-label="Sidemenu item trigger"
                  class="peer"
                  type="checkbox"
                  name="sidebar-menu-parent-item"
                />
                <div class="collapse-title">
                  <.icon name="hero-computer-desktop" class="size-4" />
                  <span class="grow">Dashboard</span>
                  <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                </div>
                <div class="collapse-content">
                  <a class="sidebar-menu-item" href="./dashboards-ecommerce.html">
                    Ecommerce
                  </a>
                  <a class="sidebar-menu-item" href="./dashboards-crm.html">
                    <span class="grow">CRM</span>
                  </a>
                  <a class="sidebar-menu-item" href="./dashboards-gen-ai.html">
                    <span class="grow">Gen AI</span>
                    <div class="border-primary/20 bg-primary/5 text-primary rounded-box ms-auto border px-1 text-[11px]">
                      New
                    </div>
                  </a>
                </div>
              </div>
              <p class="sidebar-menu-title">Apps</p>
              <div class="group collapse">
                <input
                  aria-label="Sidemenu item trigger"
                  class="peer"
                  type="checkbox"
                  name="sidebar-menu-parent-item"
                />
                <div class="collapse-title">
                  <.icon name="hero-shopping-bag" class="size-4" />
                  <span class="grow">Ecommerce</span>
                  <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                </div>
                <div class="collapse-content">
                  <a class="sidebar-menu-item" href="./apps-ecommerce-orders.html">Orders</a>
                  <a class="sidebar-menu-item" href="./apps-ecommerce-products.html">
                    Products
                  </a>
                  <a class="sidebar-menu-item" href="./apps-ecommerce-sellers.html">
                    Sellers
                  </a>
                  <a class="sidebar-menu-item" href="./apps-ecommerce-customers.html">
                    Customers
                  </a>
                  <a class="sidebar-menu-item" href="./apps-ecommerce-shops.html">Shops</a>
                </div>
              </div>
              <div class="group collapse">
                <input
                  aria-label="Sidemenu item trigger"
                  class="peer"
                  type="checkbox"
                  name="sidebar-menu-parent-item"
                />
                <div class="collapse-title">
                  <.icon name="hero-sparkles" class="size-4" />
                  <span class="grow">Gen AI</span>
                  <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                </div>
                <div class="collapse-content">
                  <a class="sidebar-menu-item" href="./apps-gen-ai-home.html">Home</a>
                  <a class="sidebar-menu-item" href="./apps-gen-ai-content.html">Content</a>
                  <a class="sidebar-menu-item" href="./apps-gen-ai-image.html">Image</a>
                  <a class="sidebar-menu-item" href="./apps-gen-ai-library.html">Library</a>
                </div>
              </div>
              <a class="sidebar-menu-item" href="./apps-file-manager.html">
                <.icon name="hero-server" class="size-4" /> File Manager
              </a>
              <a class="sidebar-menu-item" href="./apps-chat.html">
                <.icon name="hero-chat-bubble-left-right" class="size-4" /> Chat
              </a>
              <p class="sidebar-menu-title">Pages</p>
              <a class="sidebar-menu-item" href="./landing.html">
                <.icon name="hero-document" class="size-4" /> Landing
              </a>
              <div class="group collapse">
                <input
                  aria-label="Sidemenu item trigger"
                  class="peer"
                  type="checkbox"
                  name="sidebar-menu-parent-item"
                />
                <div class="collapse-title">
                  <.icon name="hero-shield-check" class="size-4" />
                  <span class="grow">Auth</span>
                  <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                </div>
                <div class="collapse-content">
                  <a class="sidebar-menu-item" href="./auth-login.html">Login</a>
                  <a class="sidebar-menu-item" href="./auth-register.html">Register</a>
                  <a class="sidebar-menu-item" href="./auth-forgot-password.html">
                    Forgot Password
                  </a>
                  <a class="sidebar-menu-item" href="./auth-reset-password.html">
                    Reset Password
                  </a>
                </div>
              </div>
              <p class="sidebar-menu-title">UI Showcase</p>
              <div class="group collapse">
                <input
                  aria-label="Sidemenu item trigger"
                  class="peer"
                  type="checkbox"
                  name="sidebar-menu-parent-item"
                />
                <div class="collapse-title">
                  <.icon name="hero-squares-2x2" class="size-4" />
                  <span class="grow">Components</span>
                  <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                </div>
                <div class="collapse-content">
                  <a class="sidebar-menu-item" href="./ui-components-accordion.html">
                    Accordion
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-alert.html">Alert</a>
                  <a class="sidebar-menu-item" href="./ui-components-avatar.html">Avatar</a>
                  <a class="sidebar-menu-item" href="./ui-components-badge.html">Badge</a>
                  <a class="sidebar-menu-item" href="./ui-components-breadcrumb.html">
                    Breadcrumb
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-button.html">Button</a>
                  <a class="sidebar-menu-item" href="./ui-components-calendar.html">
                    Calendar
                    <div class="border-primary/20 bg-primary/5 text-primary rounded-box ms-auto border px-1 text-[11px]">
                      New
                    </div>
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-countdown.html">
                    Countdown
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-drawer.html">Drawer</a>
                  <a class="sidebar-menu-item" href="./ui-components-dropdown.html">
                    Dropdown
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-indicator.html">
                    <span class="grow">Indicator</span>
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-loading.html">Loading</a>
                  <a class="sidebar-menu-item" href="./ui-components-menu.html">Menu</a>
                  <a class="sidebar-menu-item" href="./ui-components-modal.html">Modal</a>
                  <a class="sidebar-menu-item" href="./ui-components-pagination.html">
                    Pagination
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-progress.html">
                    Progress
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-step.html">Step</a>
                  <a class="sidebar-menu-item" href="./ui-components-tab.html">Tab</a>
                  <a class="sidebar-menu-item" href="./ui-components-table.html">
                    <span class="grow">Table</span>
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-timeline.html">
                    Timeline
                  </a>
                  <a class="sidebar-menu-item" href="./ui-components-toast.html">Toast</a>
                  <a class="sidebar-menu-item" href="./ui-components-tooltip.html">Tooltip</a>
                </div>
              </div>
              <div class="group collapse">
                <input
                  aria-label="Sidemenu item trigger"
                  class="peer"
                  type="checkbox"
                  name="sidebar-menu-parent-item"
                />
                <div class="collapse-title">
                  <.icon name="hero-document-text" class="size-4" />
                  <span class="grow">Forms</span>
                  <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                </div>
                <div class="collapse-content">
                  <a class="sidebar-menu-item" href="./ui-forms-checkbox.html">Checkbox</a>
                  <a class="sidebar-menu-item" href="./ui-forms-fieldset.html">
                    <span class="grow">Fieldset</span>
                  </a>
                  <a class="sidebar-menu-item" href="./ui-forms-file-input.html">
                    File Input
                  </a>
                  <a class="sidebar-menu-item" href="./ui-forms-input.html">Input</a>
                  <a class="sidebar-menu-item" href="./ui-forms-label.html">
                    <span class="grow">Label</span>
                  </a>
                  <a class="sidebar-menu-item" href="./ui-forms-radio.html">Radio</a>
                  <a class="sidebar-menu-item" href="./ui-forms-range.html">Range</a>
                  <a class="sidebar-menu-item" href="./ui-forms-rating.html">Rating</a>
                  <a class="sidebar-menu-item" href="./ui-forms-select.html">Select</a>
                  <a class="sidebar-menu-item" href="./ui-forms-textarea.html">Textarea</a>
                  <a class="sidebar-menu-item" href="./ui-forms-toggle.html">Toggle</a>
                  <a class="sidebar-menu-item" href="./ui-forms-validator.html">
                    <span class="grow">Validator</span>
                  </a>
                </div>
              </div>
              <div class="group collapse">
                <input
                  aria-label="Sidemenu item trigger"
                  class="peer"
                  type="checkbox"
                  name="sidebar-menu-parent-item"
                />
                <div class="collapse-title">
                  <.icon name="hero-chart-bar" class="size-4" />
                  <span class="grow">Charts</span>
                  <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                </div>
                <div class="collapse-content">
                  <div class="group collapse">
                    <input
                      aria-label="Sidemenu item trigger"
                      class="peer"
                      type="checkbox"
                      name="sidebar-menu-parent-item"
                    />
                    <div class="collapse-title">
                      <span class="grow">Apex</span>
                      <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                    </div>
                    <div class="collapse-content">
                      <a class="sidebar-menu-item" href="./ui-charts-apex-area.html">
                        Area
                      </a>
                      <a class="sidebar-menu-item" href="./ui-charts-apex-bar.html">
                        Bar
                      </a>
                      <a class="sidebar-menu-item" href="./ui-charts-apex-column.html">
                        Column
                      </a>
                      <a class="sidebar-menu-item" href="./ui-charts-apex-line.html">
                        Line
                      </a>
                      <a class="sidebar-menu-item" href="./ui-charts-apex-pie.html">
                        Pie
                      </a>
                    </div>
                  </div>
                </div>
              </div>
              <p class="sidebar-menu-title">Other</p>
              <div class="group collapse">
                <input
                  aria-label="Sidemenu item trigger"
                  class="peer"
                  type="checkbox"
                  name="sidebar-menu-parent-item"
                />
                <div class="collapse-title">
                  <.icon name="hero-bars-3-bottom-left" class="size-4" />
                  <span class="grow">Menu Levels</span>
                  <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                </div>
                <div class="collapse-content">
                  <a class="sidebar-menu-item" href="#">Level 1a</a>
                  <div class="group collapse">
                    <input
                      aria-label="Sidemenu item trigger"
                      class="peer"
                      type="checkbox"
                      name="sidebar-menu-parent-item"
                    />
                    <div class="collapse-title">
                      <span class="grow">Level 1b</span>
                      <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                    </div>
                    <div class="collapse-content">
                      <a class="sidebar-menu-item" href="#">Level 2a</a>
                      <div class="group collapse">
                        <input
                          aria-label="Sidemenu item trigger"
                          class="peer"
                          type="checkbox"
                          name="sidebar-menu-parent-item"
                        />
                        <div class="collapse-title">
                          <span class="grow">Level 2b</span>
                          <.icon name="hero-chevron-right" class="arrow-icon size-3.5" />
                        </div>
                        <div class="collapse-content">
                          <a class="sidebar-menu-item" href="#">Level 3a</a>
                          <a class="sidebar-menu-item" href="#">Level 3b</a>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
              <a class="sidebar-menu-item" href="https://google.com" target="_blank">
                <.icon name="hero-arrow-top-right-on-square" class="size-4" /> External Links
              </a>
              <a class="sidebar-menu-item" href="#">
                <.icon name="hero-identification" class="size-4" />
                <span class="grow">Label</span>
                <div class="inline-flex gap-2">
                  <div class="bg-secondary text-secondary-content rounded-box ms-0 px-1.5 text-[12px]">
                    +8
                  </div>
                </div>
              </a>
              <a class="sidebar-menu-item" href="https://nexus.daisyui.com/docs" target="_blank">
                <.icon name="hero-book-open" class="size-4" /> Documentation
              </a>
              -->
            </div>
          </div>
          <div class="from-base-100/60 pointer-events-none absolute start-0 end-0 bottom-0 h-7 bg-linear-to-t to-transparent">
          </div>
        </div>
        <!-- Simple logout button at bottom -->
        <div class="mt-auto mb-2 px-2">
          <.link
            href={~p"/logout"}
            method="delete"
            class="btn btn-outline btn-sm w-full flex items-center gap-2"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
            <span>Logout</span>
          </.link>
        </div>
      </div>

      <label for="layout-sidebar-toggle-trigger" id="layout-sidebar-backdrop"></label>
    </div>
    """
  end
end
