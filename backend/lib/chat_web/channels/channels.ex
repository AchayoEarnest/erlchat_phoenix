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

  @impl true
  def handle_info(:after_join, socket) do
    room_id = socket.assigns.room_id

    # BUG FIX 1: list_messages/1 does not exist. The correct function is
    # list_room_messages/1 (optionally /2 with opts).
    messages = Messages.list_room_messages(room_id)

    push(socket, "history", %{messages: messages})

    {:ok, _} =
      Presence.track(socket, socket.assigns.user_id, %{
        online_at: inspect(System.system_time(:second))
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  def handle_info({:new_message, message}, socket) do
    push(socket, "new_message", message)
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_message", %{"body" => body}, socket) do
    room_id = socket.assigns.room_id

    # BUG FIX 2: create_message/2 does not exist. The correct function is
    # create_message/1 with a single attrs map. Merge room_id and sender_id in.
    attrs = %{
      content:   body,
      room_id:   room_id,
      sender_id: socket.assigns.user_id,
      msg_type:  "text"
    }

    case Messages.create_message(attrs) do
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

  def handle_in("delete_message", %{"id" => message_id}, socket) do
    case Messages.get_message(message_id) do
      nil ->
        {:reply, {:error, %{reason: "not found"}}, socket}

      message ->
        # BUG FIX 3 (carried from previous): delete_message/2 takes a Message
        # struct + user_id (not a raw id string). Fetch first, then delete.
        case Messages.delete_message(message, socket.assigns.user_id) do
          :ok ->
            broadcast!(socket, "message_deleted", %{id: message_id})
            {:reply, :ok, socket}

          {:error, :unauthorized} ->
            {:reply, {:error, %{reason: "unauthorized"}}, socket}
        end
    end
  end
end
