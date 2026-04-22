defmodule ChatWeb.Plugs.Auth do
  @moduledoc """
  Plug that extracts and verifies the Bearer JWT token.
  Assigns :current_user to the conn on success.
  Halts with 401 on failure.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  alias Chat.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{"sub" => user_id}} <- Auth.verify_token(token),
         user when not is_nil(user) <- Auth.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized"})
        |> halt()
    end
  end
end

defmodule ChatWeb.Plugs.RequireRole do
  @moduledoc "Plug that enforces a minimum role. Use after Plugs.Auth."

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @role_hierarchy %{"user" => 0, "moderator" => 1, "admin" => 2}

  def init(opts), do: Keyword.fetch!(opts, :role)

  def call(conn, required_role) do
    user_role  = conn.assigns.current_user.role
    user_level = Map.get(@role_hierarchy, user_role, 0)
    req_level  = Map.get(@role_hierarchy, required_role, 99)

    if user_level >= req_level do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Insufficient permissions"})
      |> halt()
    end
  end
end

defmodule ChatWeb.Plugs.RateLimiter do
  @moduledoc """
  HTTP-level rate limiter (per IP).
  More lenient than the per-user WS rate limiter.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @limit  300     # 300 HTTP requests
  @window 60_000  # per minute

  def init(opts), do: opts

  def call(conn, _opts) do
    ip    = format_ip(conn.remote_ip)
    key   = {:http, ip}
    now   = System.monotonic_time(:millisecond)
    table = :rate_limits

    allowed =
      case :ets.lookup(table, key) do
        [] ->
          :ets.insert(table, {key, 1, now})
          true
        [{^key, count, window_start}] ->
          if now - window_start > @window do
            :ets.insert(table, {key, 1, now})
            true
          else
            if count < @limit do
              :ets.update_element(table, key, {2, count + 1})
              true
            else
              false
            end
          end
      end

    if allowed do
      conn
    else
      conn
      |> put_status(:too_many_requests)
      |> put_resp_header("retry-after", "60")
      |> json(%{error: "Too many requests. Try again in 60 seconds."})
      |> halt()
    end
  end

  defp format_ip(ip) when is_tuple(ip), do: ip |> Tuple.to_list() |> Enum.join(".")
  defp format_ip(ip), do: to_string(ip)
end

defmodule ChatWeb.Plugs.CORS do
  @moduledoc "Minimal CORS plug for the API."

  import Plug.Conn

  @allowed_origins [
    "http://localhost:3000",
    "https://yourdomain.com"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    allowed_origin =
      if origin in @allowed_origins or Mix.env() == :dev do
        origin || "*"
      else
        "*"
      end

    conn
    |> put_resp_header("access-control-allow-origin", allowed_origin)
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "authorization, content-type, accept")
    |> put_resp_header("access-control-max-age", "600")
    |> handle_preflight()
  end

  defp handle_preflight(%Plug.Conn{method: "OPTIONS"} = conn) do
    conn |> send_resp(204, "") |> halt()
  end
  defp handle_preflight(conn), do: conn
end
