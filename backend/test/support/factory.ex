defmodule Chat.Factory do
  @moduledoc "ExMachina factory for test data generation."

  use ExMachina.Ecto, repo: Chat.Repo
  alias Chat.Accounts.User
  alias Chat.Rooms.{Room, RoomMember}
  alias Chat.Messages.{Message, Reaction}
  alias Chat.Files.Upload

  def user_factory do
    %User{
      username:      sequence(:username, &"user_#{&1}"),
      email:         sequence(:email, &"user_#{&1}@example.com"),
      password_hash: Bcrypt.hash_pwd_salt("Password1!"),
      role:          "user",
      status:        "offline"
    }
  end

  def admin_user_factory do
    struct!(user_factory(), %{role: "admin"})
  end

  def room_factory do
    %Room{
      name:  sequence(:room_name, &"room_#{&1}"),
      type:  "public",
      owner: build(:user)
    }
  end

  def private_room_factory do
    struct!(room_factory(), %{type: "private"})
  end

  def room_member_factory do
    %RoomMember{
      room: build(:room),
      user: build(:user),
      role: "member"
    }
  end

  def message_factory do
    %Message{
      room:    build(:room),
      sender:  build(:user),
      content: sequence(:content, &"Message number #{&1}"),
      msg_type: "text",
      status:   "sent",
      edited:   false
    }
  end

  def thread_reply_factory do
    parent = build(:message)
    struct!(message_factory(), %{thread_id: parent.id})
  end

  def reaction_factory do
    %Reaction{
      message:  build(:message),
      user:     build(:user),
      reaction: "👍"
    }
  end

  def upload_factory do
    %Upload{
      uploader:      build(:user),
      filename:      sequence(:filename, &"file_#{&1}.png"),
      original_name: "photo.png",
      file_type:     "image/png",
      file_size:     1024,
      storage_key:   sequence(:storage_key, &"key_#{&1}.png"),
      url:           sequence(:url, &"http://localhost/uploads/file_#{&1}.png")
    }
  end
end
