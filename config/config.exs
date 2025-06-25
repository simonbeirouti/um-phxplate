# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Core app (database layer)
config :core,
  ecto_repos: [Core.Repo]

config :core, Core.Repo,
  username: "postgres",
  password: "123qwe!Q",
  hostname: "localhost",
  database: "phxplate_umbrella_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Public app configuration
config :public,
  generators: [context_app: false]

# Configures the public endpoint
config :public, Public.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Public.ErrorHTML, json: Public.ErrorJSON],
    layout: false
  ],
  pubsub_server: Public.PubSub,
  live_view: [signing_salt: "7VKiCGMA"]

# Admin app configuration
config :admin,
  generators: [context_app: false]

# Configures the admin endpoint
config :admin, Admin.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Admin.ErrorHTML, json: Admin.ErrorJSON],
    layout: false
  ],
  pubsub_server: Admin.PubSub,
  live_view: [signing_salt: "bq5GGUXG"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  public: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/public/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  admin: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/admin/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  public: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/public", __DIR__)
  ],
  admin: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/admin", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
