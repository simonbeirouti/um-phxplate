import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :public, Public.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hptppXNq68hwTNsd5Dz61XD/GSuCM6TRcEXwMi5RZvC2aTFkL290zmLyvnfwDQud",
  server: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :admin, Admin.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BMWo4W8xhn+n/sn1+/GuS5BceXshURHb9Xdeg8JOlXIa60SQw3/4os+YCEz4i0zH",
  server: false
