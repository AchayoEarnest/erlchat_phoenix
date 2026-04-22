defmodule Chat.Auth do
  @moduledoc """
  Authentication context.
  Handles user registration, login, and JWT token lifecycle.
  Uses Joken for HS256 JWT generation/verification.
  """

  import Ecto.Query
  alias Chat.{Repo, Accounts.User}

  @access_ttl  3_600        # 1 hour
  @refresh_ttl 2_592_000    # 30 days

  # ETS table for revoked tokens
  @blacklist :token_blacklist

  def init_blacklist do
    :ets.new(@blacklist, [:named_table, :public, :set, read_concurrency: true])
  end

  # ── Registration ─────────────────────────────────────────────

  @doc "Register a new user, returning {user, tokens} on success."
  def register(attrs) do
    with {:ok, user} <- Repo.insert(User.registration_changeset(%User{}, attrs)) do
      {:ok, tokens} = generate_tokens(user.id)
      {:ok, %{user: user, tokens: tokens}}
    end
  end

  # ── Login ────────────────────────────────────────────────────

  @doc "Authenticate with email/password, returning {user, tokens} on success."
  def login(email, password) do
    user = Repo.one(from u in User, where: u.email == ^email)

    cond do
      is_nil(user) ->
        # Constant-time: prevent user enumeration
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      not User.verify_password(user, password) ->
        {:error, :invalid_credentials}

      true ->
        # Update last_seen asynchronously
        Task.start(fn ->
          Repo.update_all(
            from(u in User, where: u.id == ^user.id),
            set: [last_seen: DateTime.utc_now(), status: "online"]
          )
        end)
        {:ok, tokens} = generate_tokens(user.id)
        {:ok, %{user: user, tokens: tokens}}
    end
  end

  # ── Token generation ─────────────────────────────────────────

  @doc "Generate access + refresh token pair for a user ID."
  def generate_tokens(user_id) do
    now = System.system_time(:second)

    access_claims = %{
      "sub"  => user_id,
      "iat"  => now,
      "exp"  => now + @access_ttl,
      "type" => "access"
    }

    refresh_claims = %{
      "sub"  => user_id,
      "iat"  => now,
      "exp"  => now + @refresh_ttl,
      "type" => "refresh"
    }

    signer = Chat.Auth.Token.signer()
    {:ok, access_token}  = Chat.Auth.Token.generate_and_sign(access_claims, signer)
    {:ok, refresh_token} = Chat.Auth.Token.generate_and_sign(refresh_claims, signer)

    {:ok, %{
      access_token:  access_token,
      refresh_token: refresh_token,
      expires_in:    @access_ttl
    }}
  end

  # ── Token verification ────────────────────────────────────────

  @doc "Verify a JWT token. Returns {:ok, claims} or {:error, reason}."
  def verify_token(token) when is_binary(token) do
    if revoked?(token) do
      {:error, :token_revoked}
    else
      case Chat.Auth.Token.verify_and_validate(token, Chat.Auth.Token.signer()) do
        {:ok, claims} ->
          now = System.system_time(:second)
          if Map.get(claims, "exp", 0) > now do
            {:ok, claims}
          else
            {:error, :token_expired}
          end
        {:error, _} ->
          {:error, :invalid_token}
      end
    end
  end
  def verify_token(_), do: {:error, :invalid_token}

  @doc "Get user_id from a valid token."
  def get_user_id(token) do
    with {:ok, claims} <- verify_token(token) do
      {:ok, claims["sub"]}
    end
  end

  @doc "Refresh an access token using a valid refresh token."
  def refresh(refresh_token) do
    with {:ok, claims} <- verify_token(refresh_token),
         "refresh"     <- Map.get(claims, "type"),
         user_id       <- claims["sub"] do
      # Revoke old refresh token (rotation)
      revoke(refresh_token)
      generate_tokens(user_id)
    else
      _ -> {:error, :invalid_refresh_token}
    end
  end

  # ── Token revocation ──────────────────────────────────────────

  @doc "Add a token to the revocation list."
  def revoke(token) do
    :ets.insert(@blacklist, {token, System.system_time(:second)})
    :ok
  end

  @doc "Check if a token has been revoked."
  def revoked?(token) do
    :ets.member(@blacklist, token)
  end

  # ── User loading ──────────────────────────────────────────────

  @doc "Fetch a user by ID."
  def get_user(id), do: Repo.get(User, id)

  @doc "Fetch a user by ID, raising if not found."
  def get_user!(id), do: Repo.get!(User, id)
end

defmodule Chat.Auth.Token do
  @moduledoc "Joken token configuration for HS256 JWT."
  use Joken.Config

  @impl true
  def token_config do
    default_claims(skip: [:iat, :exp, :iss])
  end

  def signer do
    secret =
      Application.get_env(:chat, Chat.Auth.Guardian, [])
      |> Keyword.get(:secret_key, "dev_fallback_secret_min_32_chars!!")

    Joken.Signer.create("HS256", secret)
  end
end
