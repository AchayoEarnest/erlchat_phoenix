defmodule ChatWeb.FallbackController do
  use Phoenix.Controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ChatWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: ChatWeb.ErrorJSON)
    |> render(:"401")
  end

  def call(conn, {:error, :unprocessable_entity}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ChatWeb.ErrorJSON)
    |> render(:"422")
  end
end

defmodule ChatWeb.RoomController do
  use ChatWeb, :controller

  # BUG FIX 1: Removed duplicate `action_fallback ChatWeb.FallbackController`.
  # `use ChatWeb, :controller` already injects it via the quote block in
  # ChatWeb.controller/0 (views.ex). Calling it twice caused:
  # "action_fallback can only be called a single time per controller."

  alias Chat.Rooms

  def index(conn, _params) do
    rooms = Rooms.list_user_rooms(conn.assigns.current_user.id)
    render(conn, :index, rooms: rooms)
  end

  def create(conn, %{"room" => room_params}) do
    with {:ok, room} <- Rooms.create_room(room_params, conn.assigns.current_user.id) do
      conn
      |> put_status(:created)
      |> render(:show, room: room)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, room} <- Rooms.get_room(id) do
      render(conn, :show, room: room)
    end
  end

  def update(conn, %{"id" => id, "room" => room_params}) do
    with {:ok, room} <- Rooms.get_room(id),
         {:ok, updated_room} <- Rooms.update_room(room, room_params) do
      render(conn, :show, room: updated_room)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, room} <- Rooms.get_room(id),
         {:ok, _} <- Rooms.delete_room(room) do
      send_resp(conn, :no_content, "")
    end
  end

  def join(conn, %{"id" => room_id}) do
    with :ok <- Rooms.join_room(room_id, conn.assigns.current_user.id) do
      send_resp(conn, :no_content, "")
    end
  end

  def leave(conn, %{"id" => room_id}) do
    :ok = Rooms.leave_room(room_id, conn.assigns.current_user.id)
    send_resp(conn, :no_content, "")
  end

  def kick(conn, %{"id" => room_id, "user_id" => target_id}) do
    :ok = Rooms.kick(room_id, target_id, conn.assigns.current_user.id)
    send_resp(conn, :no_content, "")
  end

  def ban(conn, %{"id" => room_id, "user_id" => target_id}) do
    :ok = Rooms.ban(room_id, target_id, conn.assigns.current_user.id)
    send_resp(conn, :no_content, "")
  end

  def mute(conn, %{"id" => room_id, "user_id" => target_id}) do
    :ok = Rooms.mute(room_id, target_id, conn.assigns.current_user.id)
    send_resp(conn, :no_content, "")
  end
end

defmodule ChatWeb.MessageController do
  use ChatWeb, :controller

  # BUG FIX 1 (same): Removed duplicate action_fallback here too.

  alias Chat.Messages

  def index(conn, %{"room_id" => room_id}) do
    messages = Messages.list_room_messages(room_id)
    render(conn, :index, messages: messages)
  end

  # BUG FIX 2: The original create/2 called Messages.create_message/2 with
  # (room_id, message_params), but Messages.create_message/1 only accepts a
  # single attrs map. Fixed by merging room_id into the params map.
  def create(conn, %{"room_id" => room_id, "message" => message_params}) do
    attrs =
      message_params
      |> Map.put("room_id", room_id)
      |> Map.put("sender_id", conn.assigns.current_user.id)

    with {:ok, message} <- Messages.create_message(attrs) do
      conn
      |> put_status(:created)
      |> render(:show, message: message)
    end
  end

  def show(conn, %{"id" => id}) do
    case Messages.get_message(id) do
      nil     -> {:error, :not_found}
      message -> render(conn, :show, message: message)
    end
  end

  def update(conn, %{"id" => id, "message" => %{"content" => content}}) do
    case Messages.get_message(id) do
      nil ->
        {:error, :not_found}
      message ->
        with {:ok, updated} <- Messages.edit_message(message, content, conn.assigns.current_user.id) do
          render(conn, :show, message: updated)
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Messages.get_message(id) do
      nil ->
        {:error, :not_found}
      message ->
        with :ok <- Messages.delete_message(message, conn.assigns.current_user.id,
                                             conn.assigns.current_user.role) do
          send_resp(conn, :no_content, "")
        end
    end
  end

  def react(conn, %{"id" => message_id, "emoji" => emoji}) do
    with :ok <- Messages.toggle_reaction(message_id, conn.assigns.current_user.id, emoji) do
      send_resp(conn, :no_content, "")
    end
  end

  def search(conn, params) do
    query   = Map.get(params, "q", "")
    room_id = Map.get(params, "room_id")
    messages = Messages.search_messages(query, room_id: room_id)
    render(conn, :index, messages: messages)
  end
end

defmodule ChatWeb.UserController do
  use ChatWeb, :controller

  # BUG FIX 1 (same): Removed duplicate action_fallback here too.

  alias Chat.Accounts

  def index(conn, _params) do
    # Placeholder — implement Accounts.list_users/0 as needed
    render(conn, :index, users: [])
  end

  def show(conn, %{"id" => id}) do
    case Accounts.get_user(id) do
      nil  -> {:error, :not_found}
      user -> render(conn, :show, user: user)
    end
  end

  def update(conn, %{"id" => id, "user" => user_params}) do
    with user when not is_nil(user) <- Accounts.get_user(id),
         {:ok, updated} <- Accounts.update_user(user, user_params) do
      render(conn, :show, user: updated)
    end
  end

  def presence(conn, %{"id" => user_id}) do
    status = Chat.Presence.get_user_status(user_id)
    render(conn, :presence, user_id: user_id, status: status)
  end

  def create(conn, %{"user" => user_params}) do
    with {:ok, user} <- Accounts.create_user(user_params),
         {:ok, token} <- Accounts.generate_token(user) do
      conn
      |> put_status(:created)
      |> render(:show, user: user, token: token)
    end
  end

  def sign_in(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate_user(email, password),
         {:ok, token} <- Accounts.generate_token(user) do
      render(conn, :show, user: user, token: token)
    end
  end
end

defmodule ChatWeb.AuthController do
  use ChatWeb, :controller

  alias Chat.Auth

  def register(conn, %{"user" => attrs}) do
    with {:ok, %{user: user, tokens: tokens}} <- Auth.register(attrs) do
      conn
      |> put_status(:created)
      |> render(:auth, user: user, tokens: tokens)
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    with {:ok, %{user: user, tokens: tokens}} <- Auth.login(email, password) do
      render(conn, :auth, user: user, tokens: tokens)
    end
  end

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    with {:ok, tokens} <- Auth.refresh(refresh_token) do
      render(conn, :tokens, tokens: tokens)
    end
  end

  def logout(conn, _params) do
    token =
      conn
      |> get_req_header("authorization")
      |> List.first("")
      |> String.replace_prefix("Bearer ", "")

    Auth.revoke(token)
    send_resp(conn, :no_content, "")
  end
end

defmodule ChatWeb.ThreadController do
  use ChatWeb, :controller

  alias Chat.Messages

  def show(conn, %{"id" => thread_id}) do
    root    = Messages.get_message(thread_id)
    replies = Messages.list_thread_messages(thread_id)

    case root do
      nil  -> {:error, :not_found}
      root -> render(conn, :show, root: root, replies: replies)
    end
  end

  def messages(conn, %{"id" => thread_id}) do
    messages = Messages.list_thread_messages(thread_id)
    render(conn, :index, messages: messages)
  end
end

defmodule ChatWeb.FileController do
  use ChatWeb, :controller

  alias Chat.Files

  def upload(conn, %{"file" => upload, "room_id" => room_id}) do
    with {:ok, file} <- Files.save(upload, conn.assigns.current_user.id, room_id) do
      conn
      |> put_status(:created)
      |> render(:show, file: file)
    end
  end

  def show(conn, %{"id" => id}) do
    case Files.get(id) do
      nil  -> {:error, :not_found}
      file -> render(conn, :show, file: file)
    end
  end

  def download(conn, %{"id" => id}) do
    case Files.get(id) do
      nil ->
        {:error, :not_found}
      file ->
        redirect(conn, external: file.url)
    end
  end
end

defmodule ChatWeb.HealthController do
  use ChatWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end

defmodule ChatWeb.AdminController do
  use ChatWeb, :controller

  def analytics(conn, _params) do
    render(conn, :analytics, stats: %{})
  end

  def users(conn, _params) do
    render(conn, :users, users: [])
  end

  def rooms(conn, _params) do
    render(conn, :rooms, rooms: [])
  end
end
