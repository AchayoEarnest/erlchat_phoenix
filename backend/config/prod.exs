# config/prod.exs
import Config

# In production, logging goes to stdout (captured by Docker/systemd)
config :logger, level: :info

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :room_id]

# Use Bandit (faster than Cowboy for most workloads)
config :chat, ChatWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

# Reduce compile-time overhead in prod
config :phoenix, :serve_endpoints, true

# Do not print debug messages in production
config :phoenix, :stacktrace_depth, 5

# Use Jason for JSON in production
config :phoenix, :json_library, Jason
