defmodule Chat.Application do
  @moduledoc """
  OTP Application entry point.

  Supervision tree:
    Chat.Repo              - Ecto PostgreSQL connection pool
    {Phoenix.PubSub, ...}  - Distributed pub/sub (local or Redis adapter)
    Chat.Presence          - Phoenix Presence (online tracking via PubSub)
    ChatWeb.Endpoint       - Bandit HTTP + WebSocket server
    Chat.RateLimiter       - ETS-backed token bucket limiter
    Chat.MessageQueue      - Offline message buffer (ETS)
    Chat.Analytics         - Telemetry event aggregator
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database pool (Ecto)
      Chat.Repo,

      # Distributed pub/sub — swap adapter to Redis for multi-node
      {Phoenix.PubSub, name: Chat.PubSub, adapter: pubsub_adapter()},

      # Phoenix Presence (built-in online/offline tracking)
      Chat.Presence,

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

  # Use Redis PubSub adapter in production if REDIS_URL is set
  defp pubsub_adapter do
    if System.get_env("REDIS_URL") do
      {Phoenix.PubSub.Redis, url: System.get_env("REDIS_URL"), node_name: node()}
    else
      Phoenix.PubSub.PG2
    end
  end
end
