defmodule Public.Router do
  use Public, :router

  import Public.UserAuth
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Public.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug :assign_current_path
  end

  defp assign_current_path(conn, _opts) do
    assign(conn, :current_path, conn.request_path)
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  @doc """
  Pipeline for basic user access.

  Ensures the current user has at least basic user privileges.
  """
  pipeline :basic do
    plug Public.Authorization, :basic
  end

  @doc """
  Pipeline for admin-level access.

  Ensures the current user has admin privileges.
  """
  pipeline :admin do
    plug Public.Authorization, :admin
  end

  scope "/", Public do
    pipe_through :browser

    get "/", PageController, :home
    get "/about", PageController, :about

    live_session :public,
        on_mount: [{Public.UserAuth, :mount_current_user}],
        layout: {Public.Layouts, :public} do
        live "/contact", ContactLive, :index
        live "/pricing", PricingLive, :index
        live "/companies", CompaniesLive, :index
        live "/companies/:id", CompanyShowLive, :show
        live "/blog", BlogLive, :index
        live "/blog/:slug", BlogShowLive, :show
      end
  end

  # Stripe callback routes
  # scope "/callbacks", Public do
  #   pipe_through :browser

  #   get "/stripe/success", StripeController, :success
  #   get "/stripe/cancel", StripeController, :cancel
  # end

  # API routes for chat functionality
  # scope "/api", Public do
  #   pipe_through :api

  #   post "/chat", ChatController, :create
  #   get "/chat/anonymous/:email", ChatController, :get_anonymous_sessions
  #   get "/chat/:id", ChatController, :get_session
  # end

  # Routes for unauthenticated users
  scope "/", Public do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      layout: {Public.Layouts, :auth},
      on_mount: [{Public.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/register", UserRegistrationLive, :new
      live "/login", UserLoginLive, :new
      live "/reset-password", UserForgotPasswordLive, :new
      live "/reset-password/:token", UserResetPasswordLive, :edit
    end

    post "/login", UserSessionController, :create
  end

  # Logout route and email confirmation
  scope "/", Public do
    pipe_through [:browser]

    delete "/logout", UserSessionController, :delete

    live_session :current_user,
      layout: {Public.Layouts, :auth},
      on_mount: [{Public.UserAuth, :mount_current_user}] do
      live "/confirm/:token", UserConfirmationLive, :edit
      live "/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  # Onboarding routes for authenticated users
  scope "/onboarding", Public do
    pipe_through [:browser, :require_authenticated_user]

    live_session :onboarding,
      layout: {Public.Layouts, :auth},
      on_mount: [
        {Public.UserAuth, :ensure_authenticated}
      ] do
      live "/", Onboarding.ProfileLive, :index
    end
  end

  # Dashboard routes with role-based access control
  # TODO: Implement dashboard LiveView modules
  # scope "/dashboard", Public do
  #   pipe_through [:browser, :require_authenticated_user]
  #   live_session :dashboard,
  #     layout: {Public.Layouts, :app},
  #     on_mount: [
  #       {Public.UserAuth, :ensure_authenticated},
  #       {Public.UserAuth, :ensure_proper_role},
  #       {Public.Live.Hooks.LayoutHooks, :default}
  #     ] do
  #     live "/", DashboardLive, :index
  #     live "/account", Dashboard.User.UserAccountLive, :index
  #     live "/account/confirm_email/:token", Dashboard.User.UserAccountLive, :confirm_email
  #     live "/invites", Dashboard.User.InvitesLive, :index
  #     live "/invites/:token", Dashboard.User.InvitesLive, :accept

  #     pipe_through [:basic]
  #     live "/basic", Dashboard.Basic.BasicLive, :index
  #     live "/basic/bookmarks", Dashboard.Basic.BookmarksLive, :index
  #     live "/companies/:id", Dashboard.Company.CompanyViewLive, :index

  #     pipe_through [:admin]
  #     live "/admin", Dashboard.Admin.AdminLive, :index
  #     live "/admin/companies", Dashboard.Admin.CompanyLive, :index
  #     live "/admin/companies/:id", Dashboard.Admin.CompanyShowLive, :index
  #   end
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:public, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Public.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
