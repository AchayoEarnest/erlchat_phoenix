defmodule Chat.AuthTest do
  use Chat.DataCase, async: true
  alias Chat.Auth

  describe "register/1" do
    test "creates a user with valid attrs" do
      assert {:ok, %{user: user, tokens: tokens}} =
               Auth.register(%{
                 "username" => "testuser",
                 "email"    => "test@example.com",
                 "password" => "Password1!"
               })

      assert user.username == "testuser"
      assert user.email    == "test@example.com"
      assert user.role     == "user"
      refute user.password_hash == "Password1!"
      assert is_binary(tokens.access_token)
      assert is_binary(tokens.refresh_token)
      assert tokens.expires_in == 3_600
    end

    test "rejects duplicate email" do
      attrs = %{"username" => "u1", "email" => "dup@example.com", "password" => "Password1!"}
      {:ok, _} = Auth.register(attrs)

      assert {:error, changeset} =
               Auth.register(%{attrs | "username" => "u2"})

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "rejects duplicate username" do
      attrs = %{"username" => "samename", "email" => "a@example.com", "password" => "Password1!"}
      {:ok, _} = Auth.register(attrs)

      assert {:error, changeset} =
               Auth.register(%{attrs | "email" => "b@example.com"})

      assert %{username: ["has already been taken"]} = errors_on(changeset)
    end

    test "rejects password shorter than 8 chars" do
      assert {:error, changeset} =
               Auth.register(%{
                 "username" => "shortpw",
                 "email"    => "shortpw@example.com",
                 "password" => "abc"
               })

      assert %{password: [_]} = errors_on(changeset)
    end
  end

  describe "login/2" do
    setup do
      {:ok, %{user: user}} =
        Auth.register(%{
          "username" => "loginuser",
          "email"    => "login@example.com",
          "password" => "MyPassword1!"
        })
      {:ok, user: user}
    end

    test "returns tokens on correct credentials" do
      assert {:ok, %{tokens: tokens}} = Auth.login("login@example.com", "MyPassword1!")
      assert is_binary(tokens.access_token)
    end

    test "returns error on wrong password" do
      assert {:error, :invalid_credentials} = Auth.login("login@example.com", "wrongpassword")
    end

    test "returns error on unknown email" do
      assert {:error, :invalid_credentials} = Auth.login("nobody@example.com", "anypassword")
    end
  end

  describe "generate_tokens/1 and verify_token/1" do
    test "round-trips a valid access token" do
      user_id = Ecto.UUID.generate()
      {:ok, %{access_token: token}} = Auth.generate_tokens(user_id)

      assert {:ok, claims} = Auth.verify_token(token)
      assert claims["sub"]  == user_id
      assert claims["type"] == "access"
    end

    test "distinguishes refresh token type" do
      user_id = Ecto.UUID.generate()
      {:ok, %{refresh_token: token}} = Auth.generate_tokens(user_id)

      assert {:ok, claims} = Auth.verify_token(token)
      assert claims["type"] == "refresh"
    end

    test "rejects a garbage token" do
      assert {:error, :invalid_token} = Auth.verify_token("not.a.jwt")
    end

    test "rejects nil token" do
      assert {:error, :invalid_token} = Auth.verify_token(nil)
    end

    test "revoked token is rejected" do
      user_id = Ecto.UUID.generate()
      {:ok, %{access_token: token}} = Auth.generate_tokens(user_id)

      :ok = Auth.revoke(token)
      assert {:error, :token_revoked} = Auth.verify_token(token)
    end
  end

  describe "refresh/1" do
    test "returns new tokens from a valid refresh token" do
      user_id = Ecto.UUID.generate()
      {:ok, %{refresh_token: rt}} = Auth.generate_tokens(user_id)

      assert {:ok, %{access_token: new_at}} = Auth.refresh(rt)
      assert is_binary(new_at)

      # Old refresh token should now be revoked
      assert {:error, :token_revoked} = Auth.verify_token(rt)
    end

    test "rejects an access token used as refresh token" do
      user_id = Ecto.UUID.generate()
      {:ok, %{access_token: at}} = Auth.generate_tokens(user_id)

      assert {:error, _} = Auth.refresh(at)
    end
  end
end

defmodule Chat.RoomsTest do
  use Chat.DataCase, async: true
  alias Chat.{Rooms, Auth}

  setup do
    {:ok, %{user: owner}} =
      Auth.register(%{
        "username" => "roomowner",
        "email"    => "owner@example.com",
        "password" => "Password1!"
      })
    {:ok, owner: owner}
  end

  describe "create_room/2" do
    test "creates room and auto-joins owner", %{owner: owner} do
      assert {:ok, room} =
               Rooms.create_room(
                 %{"name" => "testroom", "type" => "public"},
                 owner.id
               )

      assert room.name     == "testroom"
      assert room.type     == "public"
      assert room.owner_id == owner.id
      assert Rooms.member?(room.id, owner.id)
      assert Rooms.get_member_role(room.id, owner.id) == "admin"
    end

    test "rejects empty name", %{owner: owner} do
      assert {:error, changeset} =
               Rooms.create_room(%{"name" => "", "type" => "public"}, owner.id)

      assert %{name: [_]} = errors_on(changeset)
    end

    test "rejects duplicate name+type", %{owner: owner} do
      Rooms.create_room(%{"name" => "duproom", "type" => "public"}, owner.id)

      assert {:error, changeset} =
               Rooms.create_room(%{"name" => "duproom", "type" => "public"}, owner.id)

      assert %{name: [_]} = errors_on(changeset)
    end
  end

  describe "join_room/2 and leave_room/2" do
    setup %{owner: owner} do
      {:ok, room} = Rooms.create_room(%{"name" => "joinroom", "type" => "public"}, owner.id)
      {:ok, %{user: member}} =
        Auth.register(%{"username" => "member1", "email" => "member1@x.com", "password" => "Password1!"})
      {:ok, room: room, member: member}
    end

    test "join makes user a member", %{room: room, member: member} do
      refute Rooms.member?(room.id, member.id)
      assert :ok = Rooms.join_room(room.id, member.id)
      assert Rooms.member?(room.id, member.id)
    end

    test "join is idempotent", %{room: room, member: member} do
      assert :ok = Rooms.join_room(room.id, member.id)
      assert :ok = Rooms.join_room(room.id, member.id)
      assert Rooms.member?(room.id, member.id)
    end

    test "leave removes membership", %{room: room, member: member} do
      Rooms.join_room(room.id, member.id)
      assert :ok = Rooms.leave_room(room.id, member.id)
      refute Rooms.member?(room.id, member.id)
    end
  end

  describe "moderation" do
    setup %{owner: owner} do
      {:ok, room} = Rooms.create_room(%{"name" => "modroom", "type" => "public"}, owner.id)
      {:ok, %{user: target}} =
        Auth.register(%{"username" => "target", "email" => "target@x.com", "password" => "Password1!"})
      Rooms.join_room(room.id, target.id)
      {:ok, room: room, target: target}
    end

    test "ban removes and flags user", %{room: room, target: target, owner: owner} do
      assert :ok = Rooms.ban(room.id, target.id, owner.id)
      refute Rooms.member?(room.id, target.id)
    end

    test "mute flags user", %{room: room, target: target, owner: owner} do
      assert :ok = Rooms.mute(room.id, target.id, owner.id)
    end
  end
end

defmodule Chat.MessagesTest do
  use Chat.DataCase, async: true
  alias Chat.{Messages, Auth, Rooms}

  setup do
    {:ok, %{user: user}} =
      Auth.register(%{"username" => "msguser", "email" => "msg@x.com", "password" => "Password1!"})
    {:ok, room} = Rooms.create_room(%{"name" => "msgroom", "type" => "public"}, user.id)
    {:ok, user: user, room: room}
  end

  describe "create_message/1" do
    test "creates a text message", %{user: user, room: room} do
      assert {:ok, msg} =
               Messages.create_message(%{
                 room_id:   room.id,
                 sender_id: user.id,
                 content:   "Hello world!"
               })

      assert msg.content   == "Hello world!"
      assert msg.room_id   == room.id
      assert msg.sender_id == user.id
      assert msg.msg_type  == "text"
      assert msg.status    == "sent"
      refute msg.edited
    end

    test "rejects empty content", %{user: user, room: room} do
      assert {:error, changeset} =
               Messages.create_message(%{
                 room_id:   room.id,
                 sender_id: user.id,
                 content:   ""
               })
      assert %{content: [_]} = errors_on(changeset)
    end

    test "rejects content over 4096 chars", %{user: user, room: room} do
      long = String.duplicate("a", 4097)
      assert {:error, changeset} =
               Messages.create_message(%{room_id: room.id, sender_id: user.id, content: long})
      assert %{content: [_]} = errors_on(changeset)
    end
  end

  describe "edit_message/3" do
    test "allows sender to edit", %{user: user, room: room} do
      {:ok, msg} = Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "original"})
      assert {:ok, edited} = Messages.edit_message(msg, "updated", user.id)
      assert edited.content == "updated"
      assert edited.edited  == true
    end

    test "rejects edit by non-sender", %{user: user, room: room} do
      {:ok, msg} = Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "original"})
      other_id = Ecto.UUID.generate()
      assert {:error, :unauthorized} = Messages.edit_message(msg, "hacked", other_id)
    end
  end

  describe "delete_message/3" do
    test "soft-deletes by sender", %{user: user, room: room} do
      {:ok, msg} = Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "bye"})
      assert :ok = Messages.delete_message(msg, user.id)
      assert is_nil(Messages.get_message(msg.id))
    end

    test "admin can delete any message", %{user: user, room: room} do
      {:ok, msg} = Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "bye"})
      admin_id = Ecto.UUID.generate()
      assert :ok = Messages.delete_message(msg, admin_id, "admin")
    end

    test "non-owner cannot delete", %{user: user, room: room} do
      {:ok, msg} = Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "safe"})
      assert {:error, :unauthorized} = Messages.delete_message(msg, Ecto.UUID.generate())
    end
  end

  describe "toggle_reaction/3" do
    test "adds a reaction", %{user: user, room: room} do
      {:ok, msg} = Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "react!"})
      assert :ok = Messages.toggle_reaction(msg.id, user.id, "👍")
    end

    test "removes a reaction on second call", %{user: user, room: room} do
      {:ok, msg} = Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "toggle"})
      Messages.toggle_reaction(msg.id, user.id, "❤️")
      assert :ok = Messages.toggle_reaction(msg.id, user.id, "❤️")
    end
  end

  describe "search_messages/2" do
    test "finds messages by keyword", %{user: user, room: room} do
      Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "elixir is awesome"})
      Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "unrelated post"})

      results = Messages.search_messages("elixir")
      assert Enum.any?(results, &(&1.content =~ "elixir"))
    end
  end

  describe "list_room_messages/2 pagination" do
    test "returns messages in ascending order", %{user: user, room: room} do
      for i <- 1..5 do
        Messages.create_message(%{room_id: room.id, sender_id: user.id, content: "msg #{i}"})
        # Small sleep to ensure distinct timestamps
        Process.sleep(2)
      end

      msgs = Messages.list_room_messages(room.id, limit: 10)
      contents = Enum.map(msgs, & &1.content)
      assert contents == Enum.sort(contents)
    end
  end
end
