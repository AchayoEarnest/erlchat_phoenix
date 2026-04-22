# config/runtime.exs — evaluated at RUNTIME (not compile time)
# This is where all secrets and environment-specific config lives.
import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL environment variable is missing."

  pool_size = String.to_integer(System.get_env("POOL_SIZE") || "20")

  config :chat, Chat.Repo,
    url: database_url,
    pool_size: pool_size,
    ssl: true,
    ssl_opts: [verify: :verify_none]

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE environment variable is missing."

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "8080")

  config :chat, ChatWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :chat, Chat.Auth.Guardian,
    secret_key: System.fetch_env!("JWT_SECRET")
end

if config_env() in [:dev, :test] do
  config :chat, Chat.Auth.Guardian,
    secret_key: System.get_env("JWT_SECRET", "dev_secret_min_32_characters_long!!")
end

# Redis for multi-node PubSub (optional)
if redis_url = System.get_env("REDIS_URL") do
  config :chat, :redis_url, redis_url
end

# File storage
config :chat, :storage,
  type: System.get_env("STORAGE_TYPE", "local"),
  local_path: System.get_env("STORAGE_PATH", "priv/uploads"),
  base_url: System.get_env("BASE_URL", "http://localhost:8080")

# AWS S3 (if STORAGE_TYPE=s3)
config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION", "us-east-1")

config :chat, :s3_bucket, System.get_env("AWS_S3_BUCKET", "erlchat-uploads")
