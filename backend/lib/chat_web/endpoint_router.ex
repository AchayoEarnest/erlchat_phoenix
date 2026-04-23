defmodule ChatWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :chat

  socket "/socket", ChatWeb.UserSocket,
    websocket: [
      timeout: 60_000,
      max_frame_size: 1_048_576,
      check_origin: false
    ],
    longpoll: false

  if Application.compile_env(:chat, :dev_routes) do
    socket "/live", Phoenix.LiveView.Socket
    plug Phoenix.LiveDashboard.RequestLogger,
      param_key: "request_logger",
      cookie_key: "request_logger"
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, {:multipart, length: 52_428_800}, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug ChatWeb.Router
end

defmodule ChatWeb.Router do
  use ChatWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug ChatWeb.Plugs.RateLimiter
    plug ChatWeb.Plugs.CORS
  end

  pipeline :authenticated do
    plug ChatWeb.Plugs.Auth
  end

  pipeline :admin do
    plug ChatWeb.Plugs.RequireRole, role: "admin"
  end

  # ── CORS preflight — must be FIRST, before all other routes ──
  # Browsers send an OPTIONS request before every cross-origin POST/PUT/DELETE.
  # Without this the router raises NoRouteError for every preflight and login fails.
  scope "/", ChatWeb do
    pipe_through :api
    options "/*path", OptionsController, :preflight
  end

  # ── Public endpoints ──────────────────────────────────────────
  scope "/auth", ChatWeb do
    pipe_through :api

    post "/register", AuthController, :register
    post "/login",    AuthController, :login
    post "/refresh",  AuthController, :refresh
  end

  scope "/", ChatWeb do
    pipe_through :api
    get "/health", HealthController, :index
  end

  # ── Authenticated endpoints ───────────────────────────────────
  scope "/", ChatWeb do
    pipe_through [:api, :authenticated]

    post "/auth/logout", AuthController, :logout

    # Users
    get  "/users",               UserController, :index
    get  "/users/:id",           UserController, :show
    put  "/users/:id",           UserController, :update
    get  "/users/:id/presence",  UserController, :presence

    # Rooms
    get    "/rooms",              RoomController, :index
    post   "/rooms",              RoomController, :create
    get    "/rooms/:id",          RoomController, :show
    put    "/rooms/:id",          RoomController, :update
    delete "/rooms/:id",          RoomController, :delete
    post   "/rooms/:id/join",     RoomController, :join
    post   "/rooms/:id/leave",    RoomController, :leave

    # Moderation
    post "/rooms/:id/kick/:user_id", RoomController, :kick
    post "/rooms/:id/ban/:user_id",  RoomController, :ban
    post "/rooms/:id/mute/:user_id", RoomController, :mute

    # Messages
    get    "/rooms/:room_id/messages", MessageController, :index
    get    "/messages/search",         MessageController, :search
    get    "/messages/:id",            MessageController, :show
    patch  "/messages/:id",            MessageController, :update
    delete "/messages/:id",            MessageController, :delete
    post   "/messages/:id/react",      MessageController, :react

    # Threads
    get "/threads/:id",          ThreadController, :show
    get "/threads/:id/messages", ThreadController, :messages

    # Files
    post "/files/upload",       FileController, :upload
    get  "/files/:id",          FileController, :show
    get  "/files/:id/download", FileController, :download
  end

  # ── Admin-only endpoints ──────────────────────────────────────
  scope "/admin", ChatWeb do
    pipe_through [:api, :authenticated, :admin]

    get "/analytics", AdminController, :analytics
    get "/users",     AdminController, :users
    get "/rooms",     AdminController, :rooms
  end
end
