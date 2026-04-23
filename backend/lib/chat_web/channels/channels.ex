defmodule ChatWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", ChatWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Chat.Auth.verify_token(token) do
      {:ok, %{"sub" => user_id}} ->
        {:ok, assign(socket, :user_id, user_id)}
      _->
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
    room_id  = socket.assigns.room_id
    messages = Messages.list_room_messages(room_id)

    # BUG FIX: frontend listens for "history" — was previously mislabelled
    # "message_history" in the socket service. Using "history" consistently.
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
  # BUG FIX: frontend sends "new_message" with key "content" (not "body").
  # Updated pattern match from %{"body" => body} to %{"content" => content}.
  def handle_in("new_message", %{"content" => content} = payload, socket) do
    room_id  = socket.assigns.room_id
    thread_id = Map.get(payload, "thread_id")
    msg_type  = Map.get(payload, "msg_type", "text")

    attrs = %{
      content:   content,
      room_id:   room_id,
      sender_id: socket.assigns.user_id,
      msg_type:  msg_type,
      thread_id: thread_id
    }

    case Messages.create_message(attrs) do
      {:ok, message} ->
        broadcast!(socket, "new_message", message)
        {:reply, {:ok, message}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: changeset}}, socket}
    end
  end

  # BUG FIX: Frontend sends a single "typing" event with is_typing boolean.
  # Backend now handles both cases and broadcasts the appropriate event so
  # other clients receive correctly-typed start/stop signals.
  def handle_in("typing", %{"is_typing" => true}, socket) do
    broadcast_from!(socket, "typing", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  def handle_in("typing", %{"is_typing" => false}, socket) do
    broadcast_from!(socket, "stop_typing", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  # Fallback for legacy clients that omit is_typing
  def handle_in("typing", _payload, socket) do
    broadcast_from!(socket, "typing", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  def handle_in("stop_typing", _payload, socket) do
    broadcast_from!(socket, "stop_typing", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  # BUG FIX: Added missing load_messages handler for cursor-based pagination.
  # ChatWindow calls channel.push("load_messages", {before: cursor}) when the
  # user scrolls to the top. Without this handler the push timed out silently.
  def handle_in("load_messages", payload, socket) do
    room_id = socket.assigns.room_id
    before  = Map.get(payload, "before")

    opts = if before, do: [before: before], else: []
    messages = Messages.list_room_messages(room_id, opts)
    {:reply, {:ok, %{messages: messages}}, socket}
  end

  def handle_in("read_receipt", %{"message_id" => message_id}, socket) do
    Messages.mark_read(message_id, socket.assigns.user_id)
    {:noreply, socket}
  end

  def handle_in("delete_message", %{"id" => message_id}, socket) do
    case Messages.get_message(message_id) do
      nil ->
        {:reply, {:error, %{reason: "not found"}}, socket}

      message ->
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
