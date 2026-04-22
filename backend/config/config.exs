# config/config.exs — base configuration
import Config

config :chat,
  ecto_repos: [Chat.Repo],
  generators: [timestamp_type: :utc_datetime]

config :chat, ChatWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ChatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Chat.PubSub,
  live_view: [signing_salt: "erlchat_lv_salt"]

config :chat, Chat.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
