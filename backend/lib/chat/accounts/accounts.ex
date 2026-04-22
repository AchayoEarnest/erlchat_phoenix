defmodule Chat.Accounts do
  @moduledoc """
  Public Accounts context.

  BUG FIX: ChatWeb.UserController referenced Chat.Accounts.get_user/1,
  update_user/2, create_user/1, generate_token/1, and authenticate_user/2,
  but that module did not exist — all auth logic lived in Chat.Auth.

  This module provides the expected API and delegates to Chat.Auth and
  the User schema so the controllers have a stable, named context to call.
  """

  alias Chat.{Repo, Auth}
  alias Chat.Accounts.User

  # --- User retrieval ---

  @doc "Fetch a user by ID. Returns nil if not found."
  defdelegate get_user(id), to: Auth

  @doc "Fetch a user by ID, raising if not found."
  defdelegate get_user!(id), to: Auth

  # --- User creation (registration) ---

  @doc "Register a new user. Returns {:ok, user} or {:error, changeset}."
  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  # --- User updates ---

  @doc "Update a user's profile. Returns {:ok, user} or {:error, changeset}."
  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  # --- Authentication ---

  @doc "Verify email + password. Returns {:ok, %{user, tokens}} or {:error, :invalid_credentials}."
  def authenticate_user(email, password) do
    Auth.login(email, password)
  end

  @doc "Generate a JWT token pair for a user. Returns {:ok, tokens}."
  def generate_token(%User{id: id}) do
    Auth.generate_tokens(id)
  end
end
