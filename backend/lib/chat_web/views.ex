defmodule ChatWeb do
  @moduledoc """
  Entry point for ChatWeb modules. Defines the functions
  used in controllers, channels, and views.
  """

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:json]

      import Plug.Conn
      # BUG FIX: Router.Helpers was deprecated in Phoenix 1.6 and removed
      # in 1.7. The alias caused a compilation error on Phoenix 1.7+.
      # Removed entirely — use ~p sigil or hard-code paths instead.
      action_fallback ChatWeb.FallbackController
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

# ── Fallback Controller ───────────────────────────────────────

defmodule ChatWeb.FallbackController do
  use Phoenix.Controller

  # BUG FIX: Added handler for Ecto.Changeset errors so that
  # `with {:ok, _} <- Repo.insert(changeset)` failures are serialised
  # as 422 JSON rather than raising an unhandled function_clause crash.
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ChatWeb.ErrorJSON)
    |> json(%{errors: errors})
  end

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

  def call(conn, {:error, :invalid_credentials}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid email or password"})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: reason})
  end
end

# ── JSON Views ────────────────────────────────────────────────

defmodule ChatWeb.AuthJSON do
  def auth(%{user: user, tokens: tokens}) do
    %{user: render_user(user), tokens: tokens}
  end

  def tokens(%{tokens: tokens}), do: tokens
  def ok(%{message: msg}), do: %{message: msg}
  def error(%{message: msg}), do: %{error: msg}

  defp render_user(user) do
    %{
      id:          user.id,
      username:    user.username,
      email:       user.email,
      role:        user.role,
      avatar:      user.avatar,
      status:      user.status,
      inserted_at: user.inserted_at
    }
  end
end

defmodule ChatWeb.RoomJSON do
  def index(%{rooms: rooms}), do: %{data: Enum.map(rooms, &render_room/1)}
  def show(%{room: room}),    do: %{data: render_room(room)}
  def ok(%{message: msg}),    do: %{message: msg}

  def render_room(room) do
    %{
      id:           room.id,
      name:         room.name,
      description:  room.description,
      type:         room.type,
      owner_id:     room.owner_id,
      member_count: Map.get(room, :member_count, 0),
      last_message: Map.get(room, :last_message),
      inserted_at:  room.inserted_at
    }
  end
end

defmodule ChatWeb.MessageJSON do
  def index(%{messages: messages}), do: %{data: Enum.map(messages, &render_message/1)}
  def show(%{message: message}),    do: %{data: render_message(message)}
  def ok(%{message: msg}),          do: %{message: msg}

  def render_message(msg) do
    %{
      id:           msg.id,
      room_id:      msg.room_id,
      sender_id:    msg.sender_id,
      sender:       render_sender(Map.get(msg, :sender)),
      content:      msg.content,
      msg_type:     msg.msg_type,
      status:       msg.status,
      edited:       msg.edited,
      thread_id:    msg.thread_id,
      thread_count: Map.get(msg, :thread_count, 0),
      reactions:    Map.get(msg, :reactions, %{}),
      inserted_at:  msg.inserted_at
    }
  end

  defp render_sender(nil), do: nil
  defp render_sender(user) do
    %{id: user.id, username: user.username, avatar: user.avatar}
  end
end

defmodule ChatWeb.FileJSON do
  def show(%{file: file}), do: %{data: render_file(file)}

  def render_file(file) do
    %{
      id:            file.id,
      filename:      file.original_name,
      file_type:     file.file_type,
      file_size:     file.file_size,
      url:           file.url,
      thumbnail_url: file.thumbnail_url,
      inserted_at:   file.inserted_at
    }
  end
end

defmodule ChatWeb.UserJSON do
  def index(%{users: users}),  do: %{data: Enum.map(users, &render_user/1)}
  def show(%{user: user}),     do: %{data: render_user(user)}
  def presence(%{user_id: uid, status: status}), do: %{user_id: uid, status: status}

  def render_user(user) do
    %{
      id:          user.id,
      username:    user.username,
      email:       user.email,
      role:        user.role,
      avatar:      user.avatar,
      status:      user.status,
      inserted_at: user.inserted_at
    }
  end
end

defmodule ChatWeb.ThreadJSON do
  def show(%{root: root, replies: replies}) do
    %{
      data: %{
        root:    ChatWeb.MessageJSON.render_message(root),
        replies: Enum.map(replies, &ChatWeb.MessageJSON.render_message/1)
      }
    }
  end

  def index(%{messages: messages}) do
    %{data: Enum.map(messages, &ChatWeb.MessageJSON.render_message/1)}
  end
end

defmodule ChatWeb.AdminJSON do
  def analytics(%{stats: stats}), do: %{data: stats}
  def users(%{users: users}), do: %{data: Enum.map(users, &ChatWeb.UserJSON.render_user/1)}
  def rooms(%{rooms: rooms}), do: %{data: Enum.map(rooms, &ChatWeb.RoomJSON.render_room/1)}
end

defmodule ChatWeb.ErrorJSON do
  def render("404.json", _), do: %{error: "Not found"}
  def render("401.json", _), do: %{error: "Unauthorized"}
  def render("422.json", _), do: %{error: "Unprocessable entity"}
  def render("500.json", _), do: %{error: "Internal server error"}
  def render(template, _),   do: %{error: Phoenix.Controller.status_message_from_template(template)}
end
