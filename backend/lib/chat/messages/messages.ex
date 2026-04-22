defmodule Chat.Messages do
  @moduledoc """
  Messages context.
  Handles message creation, editing, deletion, reactions, threading,
  full-text search, and read receipts.
  """

  import Ecto.Query
  alias Chat.{Repo, PubSub}
  alias Chat.Messages.{Message, Reaction}

  # ── Creation ──────────────────────────────────────────────────

  @doc """
  Create a new message. On success, broadcasts to the room PubSub topic
  so all subscribers (Channel processes) receive it in real time.
  """
  def create_message(attrs) do
    with {:ok, message} <-
           %Message{}
           |> Message.changeset(attrs)
           |> Repo.insert() do
      message = Repo.preload(message, :sender)

      # Broadcast to all room subscribers via PubSub
      Phoenix.PubSub.broadcast(
        PubSub,
        "room:#{message.room_id}",
        {:new_message, message}
      )

      # Async analytics
      Task.start(fn -> Chat.Analytics.record(:message_sent, %{room_id: message.room_id}) end)

      {:ok, message}
    end
  end

  # ── Retrieval ────────────────────────────────────────────────

  @doc "Get a single message by ID."
  def get_message(id) do
    Repo.one(from m in Message, where: m.id == ^id and is_nil(m.deleted_at))
    |> Repo.preload(:sender)
  end

  def get_message!(id) do
    get_message(id) || raise Ecto.NoResultsError, queryable: Message
  end

  @doc """
  Fetch room messages (newest-first) with cursor-based pagination.
  Returns messages oldest-first for display.
  """
  def list_room_messages(room_id, opts \\ []) do
    limit  = Keyword.get(opts, :limit, 50) |> min(100)
    before = Keyword.get(opts, :before)

    query =
      from m in Message,
        where: m.room_id == ^room_id and is_nil(m.deleted_at) and is_nil(m.thread_id),
        preload: [:sender, :msg_reactions],
        order_by: [desc: m.inserted_at],
        limit: ^limit

    query =
      if before do
        where(query, [m], m.inserted_at < ^before)
      else
        query
      end

    messages =
      Repo.all(query)
      |> Enum.reverse()
      |> Enum.map(&with_thread_count/1)
      |> Enum.map(&with_reactions/1)

    messages
  end

  # ── Editing & Deletion ────────────────────────────────────────

  @doc "Edit a message. Only the sender may do this."
  def edit_message(%Message{} = message, new_content, user_id) do
    if message.sender_id == user_id do
      with {:ok, updated} <-
             message
             |> Message.edit_changeset(%{content: new_content})
             |> Repo.update() do
        Phoenix.PubSub.broadcast(
          PubSub,
          "room:#{updated.room_id}",
          {:message_edited, updated}
        )
        {:ok, updated}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc "Soft-delete a message. Sender or admin may delete."
  def delete_message(%Message{} = message, user_id, user_role \\ "user") do
    if message.sender_id == user_id or user_role in ["admin", "moderator"] do
      with {:ok, updated} <-
             Repo.update(Ecto.Changeset.change(message, deleted_at: DateTime.utc_now())) do
        Phoenix.PubSub.broadcast(
          PubSub,
          "room:#{updated.room_id}",
          {:message_deleted, updated.id}
        )
        :ok
      end
    else
      {:error, :unauthorized}
    end
  end

  # ── Reactions ────────────────────────────────────────────────

  @doc "Toggle a reaction on a message. Inserts or deletes."
  def toggle_reaction(message_id, user_id, emoji) do
    case Repo.get_by(Reaction, message_id: message_id, user_id: user_id, reaction: emoji) do
      nil ->
        # Add reaction
        %Reaction{}
        |> Reaction.changeset(%{message_id: message_id, user_id: user_id, reaction: emoji})
        |> Repo.insert()

      existing ->
        # Remove reaction
        Repo.delete(existing)
    end
    |> case do
      {:ok, _} ->
        message = get_message!(message_id)
        Phoenix.PubSub.broadcast(
          PubSub,
          "room:#{message.room_id}",
          {:reaction_updated, message_id, emoji, user_id}
        )
        :ok
      {:error, cs} ->
        {:error, cs}
    end
  end

  # ── Read receipts ─────────────────────────────────────────────

  @doc "Mark a message as read by a user."
  def mark_read(message_id, user_id) do
    Repo.insert_all(
      "message_reads",
      [%{message_id: message_id, user_id: user_id, read_at: DateTime.utc_now()}],
      on_conflict: :nothing,
      conflict_target: [:message_id, :user_id]
    )
    :ok
  end

  # ── Threads ───────────────────────────────────────────────────

  @doc "List replies for a thread (thread_id = parent message id)."
  def list_thread_messages(thread_id, limit \\ 100) do
    Repo.all(
      from m in Message,
        where: m.thread_id == ^thread_id and is_nil(m.deleted_at),
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        preload: [:sender]
    )
  end

  # ── Search ────────────────────────────────────────────────────

  @doc """
  Full-text search using PostgreSQL tsvector.
  Optionally scoped to a room_id.
  """
  def search_messages(query_str, opts \\ []) do
    room_id = Keyword.get(opts, :room_id)
    limit   = Keyword.get(opts, :limit, 50)

    base =
      from m in Message,
        where: is_nil(m.deleted_at),
        where: fragment("search_vec @@ plainto_tsquery('english', ?)", ^query_str),
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        preload: [:sender]

    base =
      if room_id do
        where(base, [m], m.room_id == ^room_id)
      else
        base
      end

    Repo.all(base)
  end

  # ── Private helpers ───────────────────────────────────────────

  defp with_thread_count(%Message{id: id} = msg) do
    count = Repo.aggregate(
      from(m in Message, where: m.thread_id == ^id and is_nil(m.deleted_at)),
      :count
    )
    %{msg | thread_count: count}
  end

  defp with_reactions(%Message{msg_reactions: reactions} = msg) do
    grouped =
      reactions
      |> Enum.group_by(& &1.reaction, & &1.user_id)

    %{msg | reactions: grouped}
  end
end
