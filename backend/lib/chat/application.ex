defmodule Chat.Application do
  @moduledoc """
  OTP Application entry point.

  Supervision tree:
    Chat.Repo            - Ecto PostgreSQL connection pool
    {Phoenix.PubSub, …}  - Distributed pub/sub
    Chat.Presence         - Phoenix Presence (online tracking via PubSub)
    Chat.TokenBlacklist  - ETS table owner for JWT revocation list
    ChatWeb.Endpoint     - Bandit HTTP + WebSocket server
    Chat.RateLimiter     - ETS-backed HTTP rate limiter
    Chat.MessageQueue    - Offline message buffer (ETS)
    Chat.Analytics       - Telemetry event aggregator
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database pool (Ecto)
      Chat.Repo,

      # BUG FIX: Phoenix.PubSub 2.x dropped the :adapter option.
      # The PG2 adapter is the built-in default — just pass a name.
      # For Redis multi-node support use phoenix_pubsub_redis separately.
      {Phoenix.PubSub, name: Chat.PubSub},

      # Phoenix Presence (built-in online/offline tracking)
      Chat.Presence,

      # BUG FIX: TokenBlacklist must start before the Endpoint so that
      # the :token_blacklist ETS table exists before any JWT is verified.
      Chat.TokenBlacklist,

      # Phoenix Endpoint (HTTP + WebSocket via Bandit)
      ChatWeb.Endpoint,

      # ETS-backed rate limiter
      Chat.RateLimiter,

      # Offline message queue
      Chat.MessageQueue,

      # Analytics telemetry
      Chat.Analytics,

      # LiveDashboard telemetry (dev/prod observability)
      {Telemetry.Metrics.ConsoleReporter, metrics: Chat.Telemetry.metrics()}
    ]

    opts = [strategy: :one_for_one, name: Chat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
