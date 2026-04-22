defmodule ChatWeb.AuthControllerTest do
  use ChatWeb.ConnCase, async: true

  describe "POST /auth/register" do
    test "creates user and returns tokens", %{conn: conn} do
      conn =
        post(conn, "/auth/register", %{
          username: "newuser",
          email:    "new@example.com",
          password: "Password1!"
        })

      assert %{"user" => user, "tokens" => tokens} = json_response(conn, 201)
      assert user["username"]          == "newuser"
      assert user["email"]             == "new@example.com"
      assert is_binary(tokens["access_token"])
      assert is_binary(tokens["refresh_token"])
      assert tokens["expires_in"]      == 3600
    end

    test "returns 422 for duplicate email", %{conn: conn} do
      attrs = %{username: "u1", email: "dup@example.com", password: "Password1!"}
      post(conn, "/auth/register", attrs)

      conn2 = post(conn, "/auth/register", %{attrs | username: "u2"})
      assert %{"errors" => _} = json_response(conn2, 422)
    end

    test "returns 422 for short password", %{conn: conn} do
      conn =
        post(conn, "/auth/register", %{
          username: "shortpw",
          email:    "short@example.com",
          password: "abc"
        })
      assert %{"errors" => %{"password" => [_]}} = json_response(conn, 422)
    end
  end

  describe "POST /auth/login" do
    setup %{conn: conn} do
      post(conn, "/auth/register", %{
        username: "logintest",
        email:    "logintest@example.com",
        password: "MyPassword1!"
      })
      :ok
    end

    test "returns tokens on correct credentials", %{conn: conn} do
      conn = post(conn, "/auth/login", %{
        email:    "logintest@example.com",
        password: "MyPassword1!"
      })
      assert %{"tokens" => %{"access_token" => token}} = json_response(conn, 200)
      assert is_binary(token)
    end

    test "returns 401 on wrong password", %{conn: conn} do
      conn = post(conn, "/auth/login", %{
        email:    "logintest@example.com",
        password: "wrongpassword"
      })
      assert %{"error" => "Invalid credentials"} = json_response(conn, 401)
    end

    test "returns 401 for unknown email", %{conn: conn} do
      conn = post(conn, "/auth/login", %{
        email:    "nobody@example.com",
        password: "anything"
      })
      assert %{"error" => _} = json_response(conn, 401)
    end
  end

  describe "POST /auth/logout" do
    test "revokes token", %{conn: conn} do
      # Register and get token
      reg_conn = post(conn, "/auth/register", %{
        username: "logoutuser",
        email:    "logout@example.com",
        password: "Password1!"
      })
      %{"tokens" => %{"access_token" => token}} = json_response(reg_conn, 201)

      # Logout
      logout_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/auth/logout")

      assert %{"message" => "Logged out"} = json_response(logout_conn, 200)

      # Token should now be rejected
      assert Chat.Auth.revoked?(token)
    end
  end

  describe "POST /auth/refresh" do
    test "returns new tokens", %{conn: conn} do
      reg_conn = post(conn, "/auth/register", %{
        username: "refreshuser",
        email:    "refresh@example.com",
        password: "Password1!"
      })
      %{"tokens" => %{"refresh_token" => rt}} = json_response(reg_conn, 201)

      conn = post(conn, "/auth/refresh", %{refresh_token: rt})
      assert %{"access_token" => new_token} = json_response(conn, 200)
      assert is_binary(new_token)
    end
  end
end

defmodule ChatWeb.RoomControllerTest do
  use ChatWeb.ConnCase, async: true

  setup %{conn: conn} do
    reg_conn = post(conn, "/auth/register", %{
      username: "roomctrl",
      email:    "roomctrl@example.com",
      password: "Password1!"
    })
    %{"tokens" => %{"access_token" => token}} = json_response(reg_conn, 201)
    authed_conn = put_req_header(conn, "authorization", "Bearer #{token}")
    {:ok, conn: authed_conn}
  end

  describe "GET /rooms" do
    test "returns empty list initially", %{conn: conn} do
      conn = get(conn, "/rooms")
      assert %{"data" => []} = json_response(conn, 200)
    end
  end

  describe "POST /rooms" do
    test "creates a public room", %{conn: conn} do
      conn = post(conn, "/rooms", %{name: "testroom", type: "public"})
      assert %{"data" => %{"name" => "testroom", "type" => "public"}} =
               json_response(conn, 201)
    end

    test "creates a private room", %{conn: conn} do
      conn = post(conn, "/rooms", %{name: "secretroom", type: "private"})
      assert %{"data" => %{"type" => "private"}} = json_response(conn, 201)
    end
  end

  describe "POST /rooms/:id/join and leave" do
    setup %{conn: conn} do
      # Create a room as another user
      other_reg = post(conn, "/auth/register", %{
        username: "otherowner",
        email:    "other@example.com",
        password: "Password1!"
      })
      %{"tokens" => %{"access_token" => other_token}} = json_response(other_reg, 201)

      other_conn = put_req_header(conn, "authorization", "Bearer #{other_token}")
      room_conn  = post(other_conn, "/rooms", %{name: "joinroom", type: "public"})
      %{"data" => %{"id" => room_id}} = json_response(room_conn, 201)
      {:ok, room_id: room_id}
    end

    test "join succeeds", %{conn: conn, room_id: room_id} do
      conn = post(conn, "/rooms/#{room_id}/join")
      assert %{"message" => "Joined room"} = json_response(conn, 200)
    end

    test "leave succeeds", %{conn: conn, room_id: room_id} do
      post(conn, "/rooms/#{room_id}/join")
      conn = post(conn, "/rooms/#{room_id}/leave")
      assert %{"message" => "Left room"} = json_response(conn, 200)
    end
  end
end

defmodule ChatWeb.MessageControllerTest do
  use ChatWeb.ConnCase, async: true
  alias Chat.{Auth, Rooms}

  setup %{conn: conn} do
    {:ok, %{user: user, tokens: tokens}} =
      Auth.register(%{
        "username" => "msgctrl",
        "email"    => "msgctrl@example.com",
        "password" => "Password1!"
      })

    {:ok, room} = Rooms.create_room(%{"name" => "msgctrlroom", "type" => "public"}, user.id)

    authed = put_req_header(conn, "authorization", "Bearer #{tokens.access_token}")
    {:ok, conn: authed, room: room, user: user}
  end

  describe "GET /rooms/:room_id/messages" do
    test "returns empty list", %{conn: conn, room: room} do
      conn = get(conn, "/rooms/#{room.id}/messages")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns messages after creation", %{conn: conn, room: room, user: user} do
      Chat.Messages.create_message(%{
        room_id: room.id, sender_id: user.id, content: "hi there"
      })
      conn = get(conn, "/rooms/#{room.id}/messages")
      assert %{"data" => [msg]} = json_response(conn, 200)
      assert msg["content"] == "hi there"
    end
  end

  describe "PATCH /messages/:id" do
    test "edits own message", %{conn: conn, room: room, user: user} do
      {:ok, msg} = Chat.Messages.create_message(%{
        room_id: room.id, sender_id: user.id, content: "original"
      })
      conn = patch(conn, "/messages/#{msg.id}", %{content: "edited"})
      assert %{"data" => %{"content" => "edited", "edited" => true}} =
               json_response(conn, 200)
    end
  end

  describe "POST /messages/:id/react" do
    test "toggles a reaction", %{conn: conn, room: room, user: user} do
      {:ok, msg} = Chat.Messages.create_message(%{
        room_id: room.id, sender_id: user.id, content: "react me"
      })
      conn = post(conn, "/messages/#{msg.id}/react", %{reaction: "👍"})
      assert %{"message" => "Reaction updated"} = json_response(conn, 200)
    end
  end

  describe "GET /messages/search" do
    test "finds messages by keyword", %{conn: conn, room: room, user: user} do
      Chat.Messages.create_message(%{
        room_id: room.id, sender_id: user.id, content: "phoenix channels are great"
      })
      conn = get(conn, "/messages/search", %{q: "phoenix"})
      assert %{"data" => results} = json_response(conn, 200)
      assert Enum.any?(results, &(&1["content"] =~ "phoenix"))
    end
  end

  describe "DELETE /messages/:id" do
    test "soft-deletes own message", %{conn: conn, room: room, user: user} do
      {:ok, msg} = Chat.Messages.create_message(%{
        room_id: room.id, sender_id: user.id, content: "delete me"
      })
      conn = delete(conn, "/messages/#{msg.id}")
      assert conn.status == 204
    end
  end
end

defmodule ChatWeb.HealthControllerTest do
  use ChatWeb.ConnCase, async: true

  test "returns ok when DB is reachable", %{conn: conn} do
    conn = get(conn, "/health")
    assert %{"status" => "ok", "db" => true} = json_response(conn, 200)
  end
end
