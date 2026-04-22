defmodule Chat.Rooms do
  @moduledoc """
  Rooms context.
  Handles room creation, membership, and moderation.
  Broadcasts membership changes via Phoenix.PubSub.
  """

  import Ecto.Query
  alias Chat.{Repo, PubSub}
  alias Chat.Rooms.{Room, RoomMember}

  # ── Room CRUD ─────────────────────────────────────────────────

  @doc "List all rooms a user is a member of."
  def list_user_rooms(user_id) do
    Repo.all(
      from r in Room,
        join: rm in RoomMember, on: rm.room_id == r.id and rm.user_id == ^user_id,
        where: rm.banned == false,
        left_join: rm2 in RoomMember, on: rm2.room_id == r.id and rm2.banned == false,
        group_by: r.id,
        select: %{r | member_count: count(rm2.user_id)}
    )
  end

  # BUG FIX: get_room/1 now returns {:ok, room} | {:error, :not_found}
  # so it can be used directly in `with` pipelines in controllers/channels.
  # The old Repo.get/2 returned nil | Room which caused the `with` pattern
  # match {:ok, room} <- Rooms.get_room(id) to never match.
  @doc "Get a single room by ID. Returns {:ok, room} or {:error, :not_found}."
  def get_room(id) do
    case Repo.get(Room, id) do
      nil  -> {:error, :not_found}
      room -> {:ok, room}
    end
  end

  @doc "Get a room, raising Ecto.NoResultsError if not found."
  def get_room!(id), do: Repo.get!(Room, id)

  @doc "Get a room with members preloaded."
  def get_room_with_members!(id) do
    Repo.get!(Room, id) |> Repo.preload(room_members: :user)
  end

  @doc "Create a new room, auto-joining the owner as admin."
  def create_room(attrs, owner_id) do
    attrs = Map.put(attrs, "owner_id", owner_id)

    Repo.transaction(fn ->
      room = Repo.insert!(Room.changeset(%Room{}, attrs))

      Repo.insert!(%RoomMember{
        room_id: room.id,
        user_id: owner_id,
        role: "admin"
      })

      room
    end)
  end

  @doc "Update room details (owner/admin only)."
  def update_room(%Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a room."
  def delete_room(%Room{} = room) do
    Repo.delete(room)
  end

  # ── Membership ────────────────────────────────────────────────

  @doc "Join a user to a room."
  def join_room(room_id, user_id) do
    %RoomMember{}
    |> RoomMember.changeset(%{room_id: room_id, user_id: user_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:room_id, :user_id])
    |> case do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(PubSub, "room:#{room_id}", {:user_joined, user_id})
        :ok
      {:error, cs} ->
        {:error, cs}
    end
  end

  @doc "Remove a user from a room."
  def leave_room(room_id, user_id) do
    Repo.delete_all(
      from rm in RoomMember,
        where: rm.room_id == ^room_id and rm.user_id == ^user_id
    )
    Phoenix.PubSub.broadcast(PubSub, "room:#{room_id}", {:user_left, user_id})
    :ok
  end

  @doc "Get all member user_ids for a room."
  def get_member_ids(room_id) do
    Repo.all(
      from rm in RoomMember,
        where: rm.room_id == ^room_id and rm.banned == false,
        select: rm.user_id
    )
  end

  @doc "Check if user is a member (and not banned)."
  def member?(room_id, user_id) do
    Repo.exists?(
      from rm in RoomMember,
        where: rm.room_id == ^room_id
          and rm.user_id == ^user_id
          and rm.banned == false
    )
  end

  @doc "Get a member's role in a room."
  def get_member_role(room_id, user_id) do
    Repo.one(
      from rm in RoomMember,
        where: rm.room_id == ^room_id and rm.user_id == ^user_id,
        select: rm.role
    )
  end

  # ── Moderation ────────────────────────────────────────────────

  @doc "Kick a user from a room."
  def kick(room_id, target_id, _by_user_id) do
    leave_room(room_id, target_id)
  end

  @doc "Ban a user from a room."
  def ban(room_id, target_id, _by_user_id) do
    Repo.update_all(
      from(rm in RoomMember, where: rm.room_id == ^room_id and rm.user_id == ^target_id),
      set: [banned: true]
    )
    Phoenix.PubSub.broadcast(PubSub, "room:#{room_id}", {:user_banned, target_id})
    :ok
  end

  @doc "Mute a user in a room."
  def mute(room_id, target_id, _by_user_id) do
    Repo.update_all(
      from(rm in RoomMember, where: rm.room_id == ^room_id and rm.user_id == ^target_id),
      set: [muted: true]
    )
    :ok
  end

  @doc "Promote or demote a member's role."
  def set_role(room_id, target_id, new_role) do
    Repo.update_all(
      from(rm in RoomMember, where: rm.room_id == ^room_id and rm.user_id == ^target_id),
      set: [role: new_role]
    )
    :ok
  end
end
