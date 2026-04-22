defmodule Chat.Analytics do
  use GenServer

  require Logger

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def record(event, payload) do
    GenServer.cast(__MODULE__, {:record, event, payload})
  end

  # --- Server Callbacks ---

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:record, :user_joined, %{room_id: room_id, user_id: user_id}}, state) do
    Logger.info("User #{user_id} joined room #{room_id}")
    new_state = update_in(state, [:joins], fn count -> (count || 0) + 1 end)
    {:noreply, new_state}
  end

  def handle_cast({:record, :user_left, %{room_id: room_id, user_id: user_id}}, state) do
    Logger.info("User #{user_id} left room #{room_id}")
    new_state = update_in(state, [:leaves], fn count -> (count || 0) + 1 end)
    {:noreply, new_state}
  end

  # FIX: Line 148 had:
  #   def handle_cast({:record, :message_sent, %{room_id: room_id}}, state) do
  # ...but room_id was never used in the function body, producing:
  # "variable "room_id" is unused"
  #
  # Fix: prefix the pattern variable with underscore: room_id: _room_id
  # This tells the compiler the variable is intentionally ignored.
  def handle_cast({:record, :message_sent, %{room_id: _room_id}}, state) do
    new_state = update_in(state, [:messages_sent], fn count -> (count || 0) + 1 end)
    {:noreply, new_state}
  end

  def handle_cast({:record, :message_deleted, %{room_id: room_id, user_id: user_id}}, state) do
    Logger.info("User #{user_id} deleted a message in room #{room_id}")
    new_state = update_in(state, [:messages_deleted], fn count -> (count || 0) + 1 end)
    {:noreply, new_state}
  end

  def handle_cast({:record, event, payload}, state) do
    Logger.warning("Unhandled analytics event: #{inspect(event)}, payload: #{inspect(payload)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end
end

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
    new_count = max(0, state.user_count - 1)
    {:noreply, %{state | user_count: new_count}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end
