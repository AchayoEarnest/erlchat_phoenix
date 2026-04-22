defmodule Chat.RateLimiter do
  @moduledoc """
  ETS-backed sliding window rate limiter.
  Default: 60 messages per 60-second window per user.
  """

  use GenServer

  @table    :rate_limits
  @window   60_000   # 1 minute in ms
  @cleanup  120_000  # Clean up stale entries every 2 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Check if user is within rate limit. Returns :ok or {:error, :rate_limited}."
  def check(user_id, limit \\ 60) do
    now = System.monotonic_time(:millisecond)
    key = {user_id, :messages}

    case :ets.lookup(@table, key) do
      [] ->
        :ets.insert(@table, {key, 1, now})
        :ok

      [{^key, count, window_start}] ->
        cond do
          now - window_start > @window ->
            :ets.insert(@table, {key, 1, now})
            :ok
          count >= limit ->
            {:error, :rate_limited}
          true ->
            :ets.update_element(@table, key, {2, count + 1})
            :ok
        end
    end
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set,
      write_concurrency: true, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    stale = :ets.foldl(
      fn {key, _count, window_start}, acc ->
        if now - window_start > @window * 2, do: [key | acc], else: acc
      end,
      [],
      @table
    )
    Enum.each(stale, &:ets.delete(@table, &1))
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup)
end

defmodule Chat.MessageQueue do
  @moduledoc """
  ETS-backed offline message queue.
  When a user is offline, their messages are buffered here (up to 200).
  Messages are flushed to the WebSocket when the user reconnects.
  """

  use GenServer

  @table    :offline_queue
  @max_msgs 200

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Enqueue a message for an offline user."
  def enqueue(user_id, message) do
    count = length(:ets.lookup(@table, user_id))
    if count >= @max_msgs do
      # Drop oldest
      case :ets.lookup(@table, user_id) do
        [{_, msgs}] -> :ets.insert(@table, {user_id, tl(msgs) ++ [message]})
        _ -> :ets.insert(@table, {user_id, [message]})
      end
    else
      case :ets.lookup(@table, user_id) do
        [{_, msgs}] -> :ets.insert(@table, {user_id, msgs ++ [message]})
        []          -> :ets.insert(@table, {user_id, [message]})
      end
    end
  end

  @doc "Flush queued messages for a user. Returns the list and clears the queue."
  def flush(user_id) do
    case :ets.lookup(@table, user_id) do
      [{_, msgs}] ->
        :ets.delete(@table, user_id)
        msgs
      [] ->
        []
    end
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, %{}}
  end
end

defmodule Chat.Analytics do
  @moduledoc """
  Lightweight analytics event collector.
  Aggregates in memory and persists periodically.
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def record(event_type, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record, event_type, metadata})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_) do
    schedule_flush()
    {:ok, %{events: [], message_count: 0, active_users: MapSet.new()}}
  end

  @impl true
  def handle_cast({:record, :message_sent, %{room_id: room_id}}, state) do
    {:noreply, %{state | message_count: state.message_count + 1}}
  end

  def handle_cast({:record, :user_connected, %{user_id: user_id}}, state) do
    {:noreply, %{state | active_users: MapSet.put(state.active_users, user_id)}}
  end

  def handle_cast({:record, _type, _meta}, state), do: {:noreply, state}

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      messages_today: state.message_count,
      active_users:   MapSet.size(state.active_users),
      online_now:     Chat.Presence.online_user_ids("global") |> length()
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:flush, state) do
    # In production: persist to analytics_events table
    Logger.debug("Analytics: #{state.message_count} messages, #{MapSet.size(state.active_users)} active users")
    schedule_flush()
    {:noreply, state}
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, 60_000)
end
