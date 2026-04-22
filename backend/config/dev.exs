# config/dev.exs
import Config

config :chat, Chat.Repo,
  username: System.get_env("DB_USER", "chatuser"),
  password: System.get_env("DB_PASS", "chatpass"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database: System.get_env("DB_NAME", "chat_dev"),
  port:     String.to_integer(System.get_env("DB_PORT", "5432")),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :chat, ChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 8080],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_not_for_production_use_here",
  watchers: []

config :logger, level: :debug
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
