defmodule ChatWeb.RoomChannelTest do
  use ChatWeb.ChannelCase, async: true
  alias ChatWeb.{UserSocket, RoomChannel}
  alias Chat.{Auth, Rooms}

  setup do
    {:ok, %{user: user, tokens: tokens}} =
      Auth.register(%{
        "username" => "chanuser",
        "email"    => "chan@example.com",
        "password" => "Password1!"
      })

    {:ok, room} =
      Rooms.create_room(%{"name" => "testchan", "type" => "public"}, user.id)

    # Build authenticated socket
    {:ok, socket} =
      connect(UserSocket, %{"token" => tokens.access_token})

    {:ok, user: user, room: room, socket: socket, tokens: tokens}
  end

  describe "join room:*" do
    test "joins a room the user is a member of", %{socket: socket, room: room} do
      assert {:ok, _, _joined_socket} = subscribe_and_join(socket, RoomChannel, "room:#{room.id}")
    end

    test "receives presence_state on join", %{socket: socket, room: room} do
      {:ok, _, _} = subscribe_and_join(socket, RoomChannel, "room:#{room.id}")
      assert_push "presence_state", _presence
    end

    test "receives message_history on join", %{socket: socket, room: room} do
      {:ok, _, _} = subscribe_and_join(socket, RoomChannel, "room:#{room.id}")
      assert_push "message_history", %{messages: _}
    end

    test "rejects join for non-member", %{socket: socket} do
      # Create a room user hasn't joined
      {:ok, %{user: owner}} =
        Auth.register(%{"username" => "owner2", "email" => "o2@x.com", "password" => "Password1!"})
      {:ok, private_room} =
        Rooms.create_room(%{"name" => "privateroom", "type" => "private"}, owner.id)

      assert {:error, %{reason: _}} =
               subscribe_and_join(socket, RoomChannel, "room:#{private_room.id}")
    end
  end

  describe "send_message event" do
    setup %{socket: socket, room: room} do
      {:ok, _, joined} = subscribe_and_join(socket, RoomChannel, "room:#{room.id}")
      {:ok, joined: joined}
    end

    test "broadcasts new_message to room", %{joined: socket} do
      ref = push(socket, "send_message", %{"content" => "hello channel!"})

      assert_reply ref, :ok, %{content: "hello channel!"}
      assert_broadcast "new_message", %{content: "hello channel!"}
    end

    test "rejects empty content", %{joined: socket} do
      ref = push(socket, "send_message", %{"content" => ""})
      assert_reply ref, :error, %{reason: _}
    end

    test "supports thread replies", %{joined: socket, room: room, user: user} do
      {:ok, parent} =
        Chat.Messages.create_message(%{
          room_id: room.id, sender_id: user.id, content: "parent"
        })

      ref = push(socket, "send_message", %{
        "content"   => "reply here",
        "thread_id" => parent.id
      })

      assert_reply ref, :ok, %{thread_id: tid}
      assert tid == parent.id
    end
  end

  describe "typing event" do
    setup %{socket: socket, room: room} do
      {:ok, _, joined} = subscribe_and_join(socket, RoomChannel, "room:#{room.id}")
      {:ok, joined: joined}
    end

    test "broadcasts typing indicator to others", %{joined: socket} do
      push(socket, "typing", %{"is_typing" => true})
      assert_broadcast "typing", %{is_typing: true}
    end

    test "does not echo back to sender", %{joined: socket} do
      push(socket, "typing", %{"is_typing" => true})
      refute_push "typing", %{}
    end
  end

  describe "load_messages event" do
    setup %{socket: socket, room: room} do
      {:ok, _, joined} = subscribe_and_join(socket, RoomChannel, "room:#{room.id}")
      {:ok, joined: joined}
    end

    test "returns paginated messages", %{joined: socket} do
      before_ts = DateTime.utc_now() |> DateTime.to_iso8601()
      ref = push(socket, "load_messages", %{"before" => before_ts})
      assert_reply ref, :ok, %{messages: msgs}
      assert is_list(msgs)
    end
  end
end
