defmodule Chat.Telemetry do
  @moduledoc "Telemetry metrics for Phoenix LiveDashboard and monitoring."

  import Telemetry.Metrics

  def metrics do
    [
      # Phoenix HTTP metrics
      summary("phoenix.endpoint.start.system_time", unit: {:native, :millisecond}),
      summary("phoenix.endpoint.stop.duration",     unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Channel metrics
      summary("phoenix.channel_join.stop.duration",
        tags: [:channel],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.stop.duration",
        tags: [:channel, :event],
        unit: {:native, :millisecond}
      ),

      # Ecto metrics
      summary("chat.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total DB query time"
      ),
      summary("chat.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "Time decoding query results"
      ),
      summary("chat.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "Time executing the query"
      ),
      summary("chat.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time waiting for a DB connection"
      ),

      # VM metrics
      last_value("vm.memory.total",            unit: {:byte, :megabyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),

      # Custom app metrics
      counter("chat.messages.created.count"),
      counter("chat.users.connected.count"),
      summary("chat.messages.content_length")
    ]
  end
end
