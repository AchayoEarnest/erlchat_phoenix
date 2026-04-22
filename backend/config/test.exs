# config/test.exs
import Config

config :chat, Chat.Repo,
  username: System.get_env("DB_USER", "chatuser"),
  password: System.get_env("DB_PASS", "chatpass"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database: System.get_env("DB_NAME", "chat_test#{System.get_env("MIX_TEST_PARTITION")}"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :chat, ChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_not_for_production_use!",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
