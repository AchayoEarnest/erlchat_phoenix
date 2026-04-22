defmodule Chat.Analytics do
  @moduledoc "Simple analytics GenServer that counts events in memory."
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  def record(event, payload) do
    GenServer.cast(__MODULE__, {:record, event, payload})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:record, :user_joined, %{room_id: room_id, user_id: user_id}}, state) do
    Logger.info("User #{user_id} joined room #{room_id}")
    {:noreply, update_in(state, [:joins], &((&1 || 0) + 1))}
  end

  def handle_cast({:record, :user_left, %{room_id: room_id, user_id: user_id}}, state) do
    Logger.info("User #{user_id} left room #{room_id}")
    {:noreply, update_in(state, [:leaves], &((&1 || 0) + 1))}
  end

  def handle_cast({:record, :message_sent, %{room_id: _room_id}}, state) do
    {:noreply, update_in(state, [:messages_sent], &((&1 || 0) + 1))}
  end

  def handle_cast({:record, :message_deleted, %{room_id: room_id, user_id: user_id}}, state) do
    Logger.info("User #{user_id} deleted a message in room #{room_id}")
    {:noreply, update_in(state, [:messages_deleted], &((&1 || 0) + 1))}
  end

  def handle_cast({:record, event, payload}, state) do
    Logger.warning("Unhandled analytics event: #{inspect(event)}, payload: #{inspect(payload)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state), do: {:reply, state, state}
end

# ---------------------------------------------------------------------------

defmodule Chat.RateLimiter do
  @moduledoc """
  ETS-backed rate limiter GenServer.
  Creates and owns the :rate_limits ETS table used by ChatWeb.Plugs.RateLimiter.
  """
  use GenServer

  @table :rate_limits

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [
      {{{:_, :_}, :_, :"$1"}, [{:<, :"$1", now - 120_000}], [true]}
    ])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60_000)
end

# ---------------------------------------------------------------------------

# BUG FIX: Chat.Auth referenced :token_blacklist ETS table (via init_blacklist/0,
# revoke/1, revoked?/1), but the table was never created in the supervision tree.
# This module owns the ETS table and must be started before any auth checks run.
defmodule Chat.TokenBlacklist do
  @moduledoc """
  GenServer that owns the :token_blacklist ETS table.
  Provides a periodic sweep to remove expired entries and prevent
  unbounded memory growth.
  """
  use GenServer

  @table :token_blacklist
  # Sweep tokens older than 31 days (refresh TTL + buffer)
  @ttl_ms 31 * 24 * 60 * 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = System.system_time(:second) - div(@ttl_ms, 1000)
    :ets.select_delete(@table, [{:"$1", [{:<, {:element, 2, :"$1"}, cutoff}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60 * 60 * 1000)
end

# ---------------------------------------------------------------------------

defmodule Chat.MessageQueue do
  @moduledoc """
  Offline message buffer backed by ETS.
  Stores messages for users who are currently disconnected.
  """
  use GenServer

  @table :message_queue

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enqueue(user_id, message) do
    existing =
      case :ets.lookup(@table, user_id) do
        [{^user_id, msgs}] -> msgs
        [] -> []
      end
    :ets.insert(@table, {user_id, [message | existing]})
    :ok
  end

  def drain(user_id) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, msgs}] ->
        :ets.delete(@table, user_id)
        Enum.reverse(msgs)
      [] ->
        []
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end

# ---------------------------------------------------------------------------

defmodule Chat.RoomSupervisor do
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_room_worker(room_id) do
    spec = {Chat.RoomWorker, room_id: room_id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_room_worker(room_id) do
    case Registry.lookup(Chat.RoomRegistry, room_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
end

defmodule Chat.RoomWorker do
  use GenServer
  require Logger

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, room_id, name: via_tuple(room_id))
  end

  defp via_tuple(room_id) do
    {:via, Registry, {Chat.RoomRegistry, room_id}}
  end

  @impl true
  def init(room_id) do
    Logger.info("Room worker started for room #{room_id}")
    {:ok, %{room_id: room_id, user_count: 0}}
  end

  @impl true
  def handle_cast({:user_joined, _user_id}, state) do
    {:noreply, %{state | user_count: state.user_count + 1}}
  end

  def handle_cast({:user_left, _user_id}, state) do
    {:noreply, %{state | user_count: max(0, state.user_count - 1)}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end
