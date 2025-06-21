import Config

# Configure Core database for testing
config :core, Core.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "phxplate_umbrella_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :web, Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7DNE35AWMAAO1GeQ5VfY+UzNncLiY7Xca1XJQB6KiueM4P4rHfkR8gWDzAisuQQG",
  server: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :admin, Admin.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "339Dugu0UpMSundxZVrndBgen8lmUaE1DqmfksiHir/AO+s4t8Pkae5yOwcoIqx7",
  server: false
