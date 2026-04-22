defmodule Chat.Analytics do
  @moduledoc """
  Simple analytics GenServer that counts events in memory.
  Registered under its module name so callers can GenServer.cast(__MODULE__, ...).
  """
  use GenServer

  require Logger

  # --- Client API ---

  def start_link(opts \\ []) do
    # BUG FIX: Must register under __MODULE__ so that record/2 can cast by name.
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  def record(event, payload) do
    GenServer.cast(__MODULE__, {:record, event, payload})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # --- Server Callbacks ---

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

  BUG FIX: This module was referenced in Chat.Application's supervision tree
  but did not exist, crashing the app at startup with:
    "The module Chat.RateLimiter was given as a child to a supervisor but it does not exist"
  """
  use GenServer

  @table :rate_limits

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create the ETS table that ChatWeb.Plugs.RateLimiter reads/writes.
    # :public so the Plug can access it from any process.
    # :set so each {ip, window} key is unique.
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    # Periodically sweep expired windows to prevent unbounded table growth.
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    # Delete entries whose window started more than 2 minutes ago.
    :ets.select_delete(@table, [
      {{{:_, :_}, :_, :"$1"}, [{:<, :"$1", now - 120_000}], [true]}
    ])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60_000)
end

# ---------------------------------------------------------------------------

defmodule Chat.MessageQueue do
  @moduledoc """
  Offline message buffer backed by ETS.
  Stores messages for users who are currently disconnected so they can be
  delivered when the user reconnects.

  BUG FIX: This module was referenced in Chat.Application's supervision tree
  but did not exist, crashing the app at startup with:
    "The module Chat.MessageQueue was given as a child to a supervisor but it does not exist"
  """
  use GenServer

  @table :message_queue

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- Client API ---

  @doc "Enqueue a message for an offline user."
  def enqueue(user_id, message) do
    existing =
      case :ets.lookup(@table, user_id) do
        [{^user_id, msgs}] -> msgs
        [] -> []
      end

    :ets.insert(@table, {user_id, [message | existing]})
    :ok
  end

  @doc "Drain and return all queued messages for a user (clears the queue)."
  def drain(user_id) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, msgs}] ->
        :ets.delete(@table, user_id)
        Enum.reverse(msgs)

      [] ->
        []
    end
  end

  # --- Server Callbacks ---

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
