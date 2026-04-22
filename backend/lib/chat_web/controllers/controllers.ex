defmodule ChatWeb.AuthController do
  use ChatWeb, :controller
  alias Chat.Auth

  action_fallback ChatWeb.FallbackController

  def register(conn, params) do
    with {:ok, %{user: user, tokens: tokens}} <- Auth.register(params) do
      conn
      |> put_status(:created)
      |> render(:auth, user: user, tokens: tokens)
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    with {:ok, %{user: user, tokens: tokens}} <- Auth.login(email, password) do
      render(conn, :auth, user: user, tokens: tokens)
    else
      {:error, :invalid_credentials} ->
        conn |> put_status(:unauthorized) |> render(:error, message: "Invalid credentials")
    end
  end

  def logout(conn, _params) do
    token = get_bearer_token(conn)
    if token, do: Auth.revoke(token)
    render(conn, :ok, message: "Logged out")
  end

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    with {:ok, tokens} <- Auth.refresh(refresh_token) do
      render(conn, :tokens, tokens: tokens)
    else
      {:error, _} ->
        conn |> put_status(:unauthorized) |> render(:error, message: "Invalid refresh token")
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end

defmodule ChatWeb.RoomController do
  use ChatWeb, :controller
  alias Chat.Rooms

  action_fallback ChatWeb.FallbackController

  def index(conn, _params) do
    rooms = Rooms.list_user_rooms(conn.assigns.current_user.id)
    render(conn, :index, rooms: rooms)
  end

  def show(conn, %{"id" => id}) do
    room = Rooms.get_room!(id)
    render(conn, :show, room: room)
  end

  def create(conn, params) do
    with {:ok, room} <- Rooms.create_room(params, conn.assigns.current_user.id) do
      conn |> put_status(:created) |> render(:show, room: room)
    end
  end

  def update(conn, %{"id" => id} = params) do
    room = Rooms.get_room!(id)
    with {:ok, updated} <- Rooms.update_room(room, params) do
      render(conn, :show, room: updated)
    end
  end

  def delete(conn, %{"id" => id}) do
    room = Rooms.get_room!(id)
    with {:ok, _} <- Rooms.delete_room(room) do
      send_resp(conn, :no_content, "")
    end
  end

  def join(conn, %{"id" => room_id}) do
    with :ok <- Rooms.join_room(room_id, conn.assigns.current_user.id) do
      render(conn, :ok, message: "Joined room")
    end
  end

  def leave(conn, %{"id" => room_id}) do
    Rooms.leave_room(room_id, conn.assigns.current_user.id)
    render(conn, :ok, message: "Left room")
  end

  def kick(conn, %{"id" => room_id, "user_id" => target_id}) do
    with :ok <- Rooms.kick(room_id, target_id, conn.assigns.current_user.id) do
      render(conn, :ok, message: "User kicked")
    end
  end

  def ban(conn, %{"id" => room_id, "user_id" => target_id}) do
    with :ok <- Rooms.ban(room_id, target_id, conn.assigns.current_user.id) do
      render(conn, :ok, message: "User banned")
    end
  end

  def mute(conn, %{"id" => room_id, "user_id" => target_id}) do
    with :ok <- Rooms.mute(room_id, target_id, conn.assigns.current_user.id) do
      render(conn, :ok, message: "User muted")
    end
  end
end

defmodule ChatWeb.MessageController do
  use ChatWeb, :controller
  alias Chat.Messages

  action_fallback ChatWeb.FallbackController

  def index(conn, %{"room_id" => room_id} = params) do
    before = Map.get(params, "before")
    limit  = Map.get(params, "limit", "50") |> String.to_integer()
    before_dt = if before, do: parse_datetime(before), else: nil

    messages = Messages.list_room_messages(room_id, before: before_dt, limit: limit)
    render(conn, :index, messages: messages)
  end

  def show(conn, %{"id" => id}) do
    message = Messages.get_message!(id)
    render(conn, :show, message: message)
  end

  def update(conn, %{"id" => id, "content" => content}) do
    message = Messages.get_message!(id)
    user    = conn.assigns.current_user

    with {:ok, updated} <- Messages.edit_message(message, content, user.id) do
      render(conn, :show, message: updated)
    end
  end

  def delete(conn, %{"id" => id}) do
    message   = Messages.get_message!(id)
    user      = conn.assigns.current_user
    user_role = Chat.Rooms.get_member_role(message.room_id, user.id)

    with :ok <- Messages.delete_message(message, user.id, user_role) do
      send_resp(conn, :no_content, "")
    end
  end

  def react(conn, %{"id" => id, "reaction" => emoji}) do
    user = conn.assigns.current_user
    with :ok <- Messages.toggle_reaction(id, user.id, emoji) do
      render(conn, :ok, message: "Reaction updated")
    end
  end

  def search(conn, params) do
    query   = Map.get(params, "q", "")
    room_id = Map.get(params, "room_id")
    messages = Messages.search_messages(query, room_id: room_id)
    render(conn, :index, messages: messages)
  end

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end

defmodule ChatWeb.FileController do
  use ChatWeb, :controller
  alias Chat.Files

  action_fallback ChatWeb.FallbackController

  def upload(conn, %{"file" => upload}) do
    user = conn.assigns.current_user

    with {:ok, file_record} <- Files.save(upload, user.id) do
      conn |> put_status(:created) |> render(:show, file: file_record)
    end
  end

  def show(conn, %{"id" => id}) do
    file = Files.get!(id)
    render(conn, :show, file: file)
  end

  def download(conn, %{"id" => id}) do
    file = Files.get!(id)
    redirect(conn, external: file.url)
  end
end

defmodule ChatWeb.UserController do
  use ChatWeb, :controller
  import Ecto.Query
  alias Chat.{Repo, Accounts.User, Presence}

  def index(conn, %{"q" => query}) do
    users = Repo.all(
      from u in User,
        where: ilike(u.username, ^"%#{query}%"),
        limit: 20,
        select: [:id, :username, :avatar, :status]
    )
    render(conn, :index, users: users)
  end

  def index(conn, _params) do
    render(conn, :index, users: [])
  end

  def show(conn, %{"id" => id}) do
    user = Repo.get!(User, id)
    render(conn, :show, user: user)
  end

  def update(conn, params) do
    user = conn.assigns.current_user
    with {:ok, updated} <- Repo.update(User.update_changeset(user, params)) do
      render(conn, :show, user: updated)
    end
  end

  def presence(conn, %{"id" => user_id}) do
    status = if Presence.user_online?(user_id), do: "online", else: "offline"
    render(conn, :presence, user_id: user_id, status: status)
  end
end

defmodule ChatWeb.ThreadController do
  use ChatWeb, :controller
  alias Chat.Messages

  def show(conn, %{"id" => thread_id}) do
    root    = Messages.get_message!(thread_id)
    replies = Messages.list_thread_messages(thread_id)
    render(conn, :show, root: root, replies: replies)
  end

  def messages(conn, %{"id" => thread_id} = params) do
    limit   = Map.get(params, "limit", "100") |> String.to_integer()
    replies = Messages.list_thread_messages(thread_id, limit)
    render(conn, :index, messages: replies)
  end
end

defmodule ChatWeb.AdminController do
  use ChatWeb, :controller
  alias Chat.Analytics

  def analytics(conn, _params) do
    stats = Analytics.get_stats()
    render(conn, :analytics, stats: stats)
  end

  def users(conn, _params) do
    import Ecto.Query
    users = Chat.Repo.all(Chat.Accounts.User)
    render(conn, :users, users: users)
  end

  def rooms(conn, _params) do
    import Ecto.Query
    rooms = Chat.Repo.all(Chat.Rooms.Room)
    render(conn, :rooms, rooms: rooms)
  end
end

defmodule ChatWeb.HealthController do
  use ChatWeb, :controller

  def index(conn, _params) do
    db_ok =
      try do
        Chat.Repo.query!("SELECT 1")
        true
      rescue
        _ -> false
      end

    status = if db_ok, do: :ok, else: :service_unavailable
    conn
    |> put_status(status)
    |> json(%{status: if(db_ok, do: "ok", else: "degraded"), db: db_ok})
  end
end

defmodule ChatWeb.FallbackController do
  use Phoenix.Controller

  def call(conn, {:error, %Ecto.Changeset{} = cs}) do
    errors = Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)

    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
  end

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(%{error: "Not found"})
  end

  def call(conn, {:error, :unauthorized}) do
    conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
  end

  def call(conn, {:error, :invalid_credentials}) do
    conn |> put_status(:unauthorized) |> json(%{error: "Invalid credentials"})
  end

  def call(conn, {:error, msg}) when is_binary(msg) do
    conn |> put_status(:bad_request) |> json(%{error: msg})
  end
end
