defmodule ChatWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", ChatWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(socket, "user socket", token, max_age: 86400) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user_id, user_id)}

      {:error, _} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end

defmodule ChatWeb.RoomChannel do
  use Phoenix.Channel

  alias Chat.Messages
  alias Chat.Presence

  @impl true
  def join("room:" <> room_id, _payload, socket) do
    socket = assign(socket, :room_id, room_id)
    send(self(), :after_join)
    {:ok, socket}
  end

  # FIX: All handle_info/2 clauses are now grouped together.
  # Previously, handle_info({:new_message, message}, socket) at line 180
  # was defined far away from the first handle_info at line 84, causing
  # the "clauses with the same name and arity should be grouped" warning.

  @impl true
  def handle_info(:after_join, socket) do
    room_id = socket.assigns.room_id
    messages = Messages.list_messages(room_id)

    push(socket, "history", %{messages: messages})

    {:ok, _} =
      Presence.track(socket, socket.assigns.user_id, %{
        online_at: inspect(System.system_time(:second))
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # FIX: Moved adjacent to the other handle_info clause above.
  # Also: this clause correctly receives the broadcasted message and
  # pushes it to the connected client.
  def handle_info({:new_message, message}, socket) do
    push(socket, "new_message", message)
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_message", %{"body" => body}, socket) do
    room_id = socket.assigns.room_id

    message_params = %{
      body: body,
      user_id: socket.assigns.user_id,
      room_id: room_id
    }

    case Messages.create_message(room_id, message_params) do
      {:ok, message} ->
        broadcast!(socket, "new_message", message)
        {:reply, :ok, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: changeset}}, socket}
    end
  end

  def handle_in("typing", _payload, socket) do
    broadcast_from!(socket, "typing", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  def handle_in("stop_typing", _payload, socket) do
    broadcast_from!(socket, "stop_typing", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  # FIX: Line 146 had:
  #   room_id = socket.assigns.room_id
  # ...but room_id was never used in that clause's body.
  # Fix: prefix the unused variable with underscore, OR (better) just
  # remove the binding entirely and use socket.assigns.room_id inline
  # only where needed. Here we show the corrected pattern-match approach.
  def handle_in("delete_message", %{"id" => message_id}, socket) do
    # FIX: was `room_id = socket.assigns.room_id` (unused). Removed.
    case Messages.delete_message(message_id, socket.assigns.user_id) do
      {:ok, _} ->
        broadcast!(socket, "message_deleted", %{id: message_id})
        {:reply, :ok, socket}

      {:error, :unauthorized} ->
        {:reply, {:error, %{reason: "unauthorized"}}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not found"}}, socket}
    end
  end
end
