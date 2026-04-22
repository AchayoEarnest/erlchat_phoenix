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

  # FIX: Only ONE action_fallback declaration per controller.
  # Previously this was declared twice, causing the compilation error:
  # "action_fallback can only be called a single time per controller."
  action_fallback ChatWeb.FallbackController

  alias Chat.Rooms

  def index(conn, _params) do
    rooms = Rooms.list_rooms()
    render(conn, :index, rooms: rooms)
  end

  def create(conn, %{"room" => room_params}) do
    with {:ok, room} <- Rooms.create_room(room_params) do
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
end

defmodule ChatWeb.MessageController do
  use ChatWeb, :controller

  # FIX: Only one action_fallback here too.
  action_fallback ChatWeb.FallbackController

  alias Chat.Messages

  def index(conn, %{"room_id" => room_id}) do
    messages = Messages.list_messages(room_id)
    render(conn, :index, messages: messages)
  end

  def create(conn, %{"room_id" => room_id, "message" => message_params}) do
    with {:ok, message} <- Messages.create_message(room_id, message_params) do
      conn
      |> put_status(:created)
      |> render(:show, message: message)
    end
  end
end

defmodule ChatWeb.UserController do
  use ChatWeb, :controller

  action_fallback ChatWeb.FallbackController

  alias Chat.Accounts

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
