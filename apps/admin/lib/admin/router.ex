defmodule Admin.Router do
  use Admin, :router

  import Core.Auth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Admin.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Routes for unauthenticated users
  scope "/", Admin do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{Core.Auth, :redirect_if_user_is_authenticated}] do
      live "/", UserLoginLive, :new
      live "/reset-password", UserForgotPasswordLive, :new
      live "/reset-password/:token", UserResetPasswordLive, :edit
    end

    post "/login", UserSessionController, :create
  end

  # Routes for authenticated users (non-dashboard)
  scope "/", Admin do
    pipe_through [:browser, :require_authenticated_user]

    delete "/logout", UserSessionController, :delete
  end

  # Dashboard routes with dashboard layout
  scope "/dashboard", Admin do
    pipe_through [:browser, :require_authenticated_user]

    # Main dashboard
    live_session :dashboard,
      layout: {Admin.Layouts, :dashboard},
      on_mount: [
        {Core.Auth, :mount_current_user},
        {Core.Auth, :ensure_authenticated},
        {Admin.Live.Hooks.LayoutHooks, :default}
      ] do
      live "/", DashboardLive, :index
    end

    # Super Admin Platform Management
    live_session :platform_management,
      layout: {Admin.Layouts, :dashboard},
      on_mount: [
        {Core.Auth, :mount_current_user},
        {Core.Auth, :ensure_authenticated},
        {Admin.Live.Hooks.LayoutHooks, :default}
      ] do
      live "/super_admin", SuperAdmin.DashboardLive, :index
      live "/super_admin/subscriptions", SuperAdmin.SubscriptionsLive, :index
      live "/super_admin/blogs", SuperAdmin.BlogsLive, :index
      live "/super_admin/companies", SuperAdmin.CompaniesLive, :index
      live "/super_admin/platform-settings", SuperAdmin.PlatformSettingsLive, :index
    end

    # Super Admin Customer Engagement
    live_session :customer_engagement,
      layout: {Admin.Layouts, :dashboard},
      on_mount: [
        {Core.Auth, :mount_current_user},
        {Core.Auth, :ensure_authenticated},
        {Admin.Live.Hooks.LayoutHooks, :default}
      ] do
      live "/super_admin/chat", SuperAdmin.ChatLive, :index
      live "/super_admin/feature-feedbacks", SuperAdmin.FeatureFeedbacksLive, :index
      live "/super_admin/users", SuperAdmin.UsersLive, :index
    end

    # Super Admin AI Management
    live_session :ai_management,
      layout: {Admin.Layouts, :dashboard},
      on_mount: [
        {Core.Auth, :mount_current_user},
        {Core.Auth, :ensure_authenticated},
        {Admin.Live.Hooks.LayoutHooks, :default}
      ] do
      live "/super_admin/ai-chat", SuperAdmin.AiChatLive, :index
      live "/super_admin/ai-prompts", SuperAdmin.AiPromptsLive, :index
      live "/super_admin/ai-evals", SuperAdmin.AiEvalsLive, :index
      live "/super_admin/ai-eval-results", SuperAdmin.AiEvalResultsLive, :index
      live "/super_admin/ai-results", SuperAdmin.AiResultsLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", Admin do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:admin, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Admin.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
