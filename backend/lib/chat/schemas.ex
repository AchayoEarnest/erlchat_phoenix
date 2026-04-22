defmodule Chat.Accounts.User do
  @moduledoc "User schema with role-based access control."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [:id, :username, :email, :role, :avatar, :status, :inserted_at]}

  schema "users" do
    field :username,      :string
    field :email,         :string
    field :password_hash, :string
    field :password,      :string, virtual: true
    field :role,          :string, default: "user"
    field :avatar,        :string
    field :status,        :string, default: "offline"
    field :last_seen,     :utc_datetime

    has_many :messages,      Chat.Messages.Message, foreign_key: :sender_id
    has_many :room_members,  Chat.Rooms.RoomMember
    has_many :rooms,         through: [:room_members, :room]

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for registration."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password, :role])
    |> validate_required([:username, :email, :password])
    |> validate_length(:username, min: 3, max: 64)
    |> validate_length(:password, min: 8, max: 128)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> validate_inclusion(:role, ["admin", "moderator", "user"])
    |> put_password_hash()
  end

  @doc "Changeset for profile updates."
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :avatar, :status])
    |> validate_length(:username, min: 3, max: 64)
    |> validate_inclusion(:status, ["online", "offline", "away"])
    |> unique_constraint(:username)
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: pw}} = cs) do
    put_change(cs, :password_hash, Bcrypt.hash_pwd_salt(pw))
  end
  defp put_password_hash(cs), do: cs

  @doc "Verify a plaintext password against the stored hash."
  def verify_password(%__MODULE__{password_hash: hash}, password) do
    Bcrypt.verify_pass(password, hash)
  end
end

defmodule Chat.Rooms.Room do
  @moduledoc "Chat room schema."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [:id, :name, :description, :type, :owner_id, :inserted_at]}

  schema "rooms" do
    field :name,         :string
    field :description,  :string
    field :type,         :string, default: "public"

    # BUG FIX: member_count is used as a virtual select in list_user_rooms/1.
    # Without this field the struct update %{r | member_count: ...} crashes.
    field :member_count, :integer, virtual: true, default: 0

    belongs_to :owner, Chat.Accounts.User
    has_many   :room_members, Chat.Rooms.RoomMember
    has_many   :members,      through: [:room_members, :user]
    has_many   :messages,     Chat.Messages.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :description, :type, :owner_id])
    |> validate_required([:name, :type, :owner_id])
    |> validate_length(:name, min: 1, max: 128)
    |> validate_inclusion(:type, ["public", "private", "direct"])
    |> unique_constraint([:name, :type],
         name: :rooms_name_type_index,
         message: "A room with that name already exists")
  end
end

defmodule Chat.Rooms.RoomMember do
  @moduledoc "Room membership join table with role and moderation flags."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "room_members" do
    belongs_to :room, Chat.Rooms.Room,    primary_key: true
    belongs_to :user, Chat.Accounts.User, primary_key: true

    field :role,   :string, default: "member"
    field :muted,  :boolean, default: false
    field :banned, :boolean, default: false

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:room_id, :user_id, :role, :muted, :banned])
    |> validate_required([:room_id, :user_id])
    |> validate_inclusion(:role, ["admin", "moderator", "member"])
    |> unique_constraint([:room_id, :user_id])
  end
end

defmodule Chat.Messages.Message do
  @moduledoc "Chat message with threading, reactions, and soft delete."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [
    :id, :room_id, :sender_id, :content, :msg_type,
    :thread_id, :status, :edited, :inserted_at, :reactions, :thread_count
  ]}

  schema "messages" do
    field :content,      :string
    field :msg_type,     :string, default: "text"
    field :status,       :string, default: "sent"
    field :edited,       :boolean, default: false
    field :deleted_at,   :utc_datetime

    field :thread_count, :integer, virtual: true, default: 0
    field :reactions,    :map,     virtual: true, default: %{}

    belongs_to :room,   Chat.Rooms.Room
    belongs_to :sender, Chat.Accounts.User, foreign_key: :sender_id
    belongs_to :thread, __MODULE__, foreign_key: :thread_id

    has_many :replies,       __MODULE__, foreign_key: :thread_id
    has_many :msg_reactions, Chat.Messages.Reaction

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:room_id, :sender_id, :content, :msg_type, :thread_id])
    |> validate_required([:room_id, :sender_id, :content])
    |> validate_length(:content, min: 1, max: 4096)
    |> validate_inclusion(:msg_type, ["text", "image", "file", "system"])
  end

  def edit_changeset(message, attrs) do
    message
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> validate_length(:content, min: 1, max: 4096)
    |> put_change(:edited, true)
  end
end

defmodule Chat.Messages.Reaction do
  @moduledoc "Emoji reactions on messages."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "message_reactions" do
    belongs_to :message, Chat.Messages.Message, primary_key: true
    belongs_to :user,    Chat.Accounts.User,    primary_key: true

    field :reaction, :string, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:message_id, :user_id, :reaction])
    |> validate_required([:message_id, :user_id, :reaction])
    |> validate_length(:reaction, max: 64)
    |> unique_constraint([:message_id, :user_id, :reaction])
  end
end

defmodule Chat.Files.Upload do
  @moduledoc "Uploaded file metadata."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [
    :id, :filename, :original_name, :file_type, :file_size, :url, :thumbnail_url, :inserted_at
  ]}

  schema "files" do
    field :filename,       :string
    field :original_name,  :string
    field :file_type,      :string
    field :file_size,      :integer
    field :storage_key,    :string
    field :url,            :string
    field :thumbnail_url,  :string

    belongs_to :uploader, Chat.Accounts.User
    belongs_to :room,     Chat.Rooms.Room

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [:uploader_id, :room_id, :filename, :original_name,
                    :file_type, :file_size, :storage_key, :url, :thumbnail_url])
    |> validate_required([:uploader_id, :filename, :file_type, :file_size, :url])
    |> validate_number(:file_size, greater_than: 0, less_than_or_equal_to: 52_428_800)
  end
end
