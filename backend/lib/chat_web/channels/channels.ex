defmodule ChatWeb.UserSocket do
  @moduledoc """
  Phoenix Socket entry point.
  Authenticates the connection via token and routes to channels.

  The token is passed as a URL param or in the connect payload:
    socket.connect({ token: "..." })
  """

  use Phoenix.Socket

  # Each room gets its own channel process
  channel "room:*",  ChatWeb.RoomChannel

  # One channel for user-level events (presence, DMs, notifications)
  channel "user:*",  ChatWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Chat.Auth.verify_token(token) do
      {:ok, %{"sub" => user_id, "type" => "access"}} ->
        user = Chat.Auth.get_user(user_id)
        socket = assign(socket, :current_user, user)
        {:ok, socket}

      {:error, reason} ->
        require Logger
        Logger.warning("Socket auth failed: #{inspect(reason)}")
        :error
    end
  end

  def connect(_params, _socket, _info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end

defmodule ChatWeb.RoomChannel do
  @moduledoc """
  Phoenix Channel for a single chat room.

  Each room topic ("room:<room_id>") gets ONE channel process per connected user.
  Phoenix PubSub handles cross-node broadcast transparently.

  Client-side events handled:
    "send_message"  - new chat message
    "typing"        - typing indicator
    "read_receipt"  - mark message as read
    "load_messages" - fetch older messages (pagination)

  Server pushes:
    "new_message"      - broadcast to room
    "message_edited"   - broadcast updated message
    "message_deleted"  - broadcast deletion
    "typing"           - broadcast typing indicator
    "presence_state"   - full presence snapshot on join
    "presence_diff"    - incremental presence updates
    "reaction_updated" - broadcast reaction toggle
  """

  use Phoenix.Channel
  require Logger
  alias Chat.{Messages, Rooms, RateLimiter, MessageQueue, Presence}

  @impl true
  def join("room:" <> room_id, _params, socket) do
    user   = socket.assigns.current_user

    # Verify membership
    if Rooms.member?(room_id, user.id) do
      socket = assign(socket, :room_id, room_id)

      # Deliver offline messages after join
      send(self(), :after_join)

      {:ok, socket}
    else
      {:error, %{reason: "not a member of this room"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    user    = socket.assigns.current_user
    room_id = socket.assigns.room_id

    # Track presence
    {:ok, _} = Presence.track(socket, user.id, %{
      status:   "online",
      username: user.username,
      avatar:   user.avatar,
      phx_ref:  socket.id
    })

    # Push full presence list to the joining client
    push(socket, "presence_state", Presence.list(socket))

    # Flush queued offline messages
    queued = MessageQueue.flush(user.id)
    Enum.each(queued, fn msg ->
      push(socket, "new_message", format_message(msg))
    end)

    # Push recent messages for initial load
    messages = Messages.list_room_messages(room_id, limit: 50)
    push(socket, "message_history", %{messages: Enum.map(messages, &format_message/1)})

    {:noreply, socket}
  end

  # ── Incoming: send_message ────────────────────────────────────

  @impl true
  def handle_in("send_message", %{"content" => content} = params, socket) do
    user    = socket.assigns.current_user
    room_id = socket.assigns.room_id

    with :ok <- RateLimiter.check(user.id),
         {:ok, message} <- Messages.create_message(%{
           room_id:   room_id,
           sender_id: user.id,
           content:   content,
           msg_type:  Map.get(params, "msg_type", "text"),
           thread_id: Map.get(params, "thread_id")
         }) do

      # Notify offline room members
      notify_offline_members(room_id, user.id, message)

      # Broadcast handled by create_message → PubSub → handle_info
      {:reply, {:ok, format_message(message)}, socket}
    else
      {:error, :rate_limited} ->
        {:reply, {:error, %{reason: "Rate limited. Slow down."}}, socket}

      {:error, %Ecto.Changeset{} = cs} ->
        {:reply, {:error, %{reason: format_errors(cs)}}, socket}
    end
  end

  # ── Incoming: typing indicator ────────────────────────────────

  def handle_in("typing", %{"is_typing" => is_typing}, socket) do
    user    = socket.assigns.current_user
    room_id = socket.assigns.room_id

    broadcast_from!(socket, "typing", %{
      user_id:  user.id,
      username: user.username,
      is_typing: is_typing
    })

    {:noreply, socket}
  end

  # ── Incoming: read receipt ────────────────────────────────────

  def handle_in("read_receipt", %{"message_id" => message_id}, socket) do
    Messages.mark_read(message_id, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  # ── Incoming: load older messages (pagination) ─────────────────

  def handle_in("load_messages", %{"before" => before_ts}, socket) do
    room_id = socket.assigns.room_id

    before = case DateTime.from_iso8601(before_ts) do
      {:ok, dt, _} -> dt
      _ -> nil
    end

    messages = Messages.list_room_messages(room_id, before: before, limit: 50)
    {:reply, {:ok, %{messages: Enum.map(messages, &format_message/1)}}, socket}
  end

  # ── PubSub broadcast events → channel push ────────────────────

  def handle_info({:new_message, message}, socket) do
    push(socket, "new_message", format_message(message))
    {:noreply, socket}
  end

  def handle_info({:message_edited, message}, socket) do
    push(socket, "message_edited", format_message(message))
    {:noreply, socket}
  end

  def handle_info({:message_deleted, message_id}, socket) do
    push(socket, "message_deleted", %{id: message_id})
    {:noreply, socket}
  end

  def handle_info({:reaction_updated, message_id, emoji, user_id}, socket) do
    push(socket, "reaction_updated", %{
      message_id: message_id,
      reaction:   emoji,
      user_id:    user_id
    })
    {:noreply, socket}
  end

  def handle_info({:user_joined, user_id}, socket) do
    push(socket, "user_joined", %{user_id: user_id})
    {:noreply, socket}
  end

  def handle_info({:user_left, user_id}, socket) do
    push(socket, "user_left", %{user_id: user_id})
    {:noreply, socket}
  end

  def handle_info({:user_banned, user_id}, socket) do
    if socket.assigns.current_user.id == user_id do
      push(socket, "kicked", %{reason: "You have been banned"})
    end
    {:noreply, socket}
  end

  # ── Terminate ─────────────────────────────────────────────────

  @impl true
  def terminate(_reason, socket) do
    Logger.debug("User #{socket.assigns.current_user.id} left room #{socket.assigns.room_id}")
    :ok
  end

  # ── Helpers ───────────────────────────────────────────────────

  defp format_message(message) do
    %{
      id:          message.id,
      room_id:     message.room_id,
      sender_id:   message.sender_id,
      sender:      format_user(Map.get(message, :sender)),
      content:     message.content,
      msg_type:    message.msg_type,
      status:      message.status,
      edited:      message.edited,
      thread_id:   message.thread_id,
      thread_count: Map.get(message, :thread_count, 0),
      reactions:   Map.get(message, :reactions, %{}),
      inserted_at: message.inserted_at
    }
  end

  defp format_user(nil), do: nil
  defp format_user(user) do
    %{id: user.id, username: user.username, avatar: user.avatar}
  end

  defp format_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp notify_offline_members(room_id, sender_id, message) do
    member_ids = Rooms.get_member_ids(room_id)

    offline_ids =
      Enum.filter(member_ids, fn id ->
        id != sender_id and not Presence.user_online?(id)
      end)

    Enum.each(offline_ids, fn user_id ->
      MessageQueue.enqueue(user_id, message)
    end)
  end
end

defmodule ChatWeb.UserChannel do
  @moduledoc """
  Per-user channel for direct messages, notifications, and global presence.
  Topic: "user:<user_id>"
  Users may only join their own user channel (enforced in join/3).
  """

  use Phoenix.Channel
  alias Chat.Presence

  @impl true
  def join("user:" <> user_id, _params, socket) do
    if socket.assigns.current_user.id == user_id do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "cannot join another user's channel"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Track global presence
    {:ok, _} = Presence.track(socket, socket.assigns.current_user.id, %{
      status: "online",
      username: socket.assigns.current_user.username
    })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{pong: true}}, socket}
  end
end
