defmodule Chat.Presence do
  @moduledoc """
  Phoenix Presence for real-time online/offline tracking.

  Presence is built on top of Phoenix.PubSub and uses a CRDT-based
  algorithm to sync state across nodes without a central coordinator.

  Usage:
    # Track a user when they connect
    Chat.Presence.track(socket, user_id, %{status: "online", username: username})

    # List who's online in a room
    Chat.Presence.list("room:general")
    # => %{"user_id" => %{metas: [%{status: "online"}]}}
  """

  use Phoenix.Presence,
    otp_app: :chat,
    pubsub_server: Chat.PubSub

  @doc "Get list of online user IDs for a given topic."
  def online_user_ids(topic) do
    topic
    |> list()
    |> Map.keys()
  end

  @doc "Check if a specific user is online anywhere."
  def user_online?(user_id) do
    case get(Chat.Presence, "users:#{user_id}") do
      %{metas: [_ | _]} -> true
      _ -> false
    end
  end

  @doc "Get aggregated presence for a room."
  def room_presence(room_id) do
    "room:#{room_id}"
    |> list()
    |> Enum.map(fn {user_id, %{metas: metas}} ->
      %{user_id: user_id, status: List.first(metas)[:status] || "online"}
    end)
  end
end
