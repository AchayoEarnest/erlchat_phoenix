defmodule Chat.Repo.Migrations.CreateRoomMembers do
  use Ecto.Migration

  def change do
    create table(:room_members, primary_key: false) do
      add :room_id,   references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id,   references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role,      :string,  null: false, default: "member"
      add :muted,     :boolean, null: false, default: false
      add :banned,    :boolean, null: false, default: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create primary_key(:room_members, [:room_id, :user_id])
    create index(:room_members, [:user_id])
    create index(:room_members, [:room_id], where: "banned = false")

    create constraint(:room_members, :valid_role,
      check: "role IN ('admin', 'moderator', 'member')")
  end
end

defmodule Chat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id,         :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :room_id,    references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :sender_id,  references(:users, type: :binary_id, on_delete: :nilify_all)
      add :content,    :text,    null: false
      add :msg_type,   :string,  null: false, default: "text"
      add :thread_id,  references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :status,     :string,  null: false, default: "sent"
      add :edited,     :boolean, null: false, default: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:room_id, :inserted_at],
      where: "deleted_at IS NULL",
      name: :messages_room_timeline_index)
    create index(:messages, [:sender_id], where: "deleted_at IS NULL")
    create index(:messages, [:thread_id], where: "thread_id IS NOT NULL")

    # Full-text search: generated tsvector column + GIN index
    execute """
      ALTER TABLE messages
        ADD COLUMN search_vec tsvector
        GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
    """,
    "ALTER TABLE messages DROP COLUMN search_vec"

    execute """
      CREATE INDEX messages_search_gin_index
        ON messages USING GIN (search_vec)
        WHERE deleted_at IS NULL
    """,
    "DROP INDEX IF EXISTS messages_search_gin_index"

    create constraint(:messages, :valid_msg_type,
      check: "msg_type IN ('text', 'image', 'file', 'system')")
    create constraint(:messages, :valid_status,
      check: "status IN ('sending', 'sent', 'delivered', 'read', 'failed')")
    create constraint(:messages, :content_not_empty,
      check: "length(trim(content)) > 0")
  end
end

defmodule Chat.Repo.Migrations.CreateMessageReads do
  use Ecto.Migration

  def change do
    create table(:message_reads, primary_key: false) do
      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id,    references(:users, type: :binary_id, on_delete: :delete_all),    null: false
      add :read_at,    :utc_datetime, null: false

      # No updated_at needed
    end

    create primary_key(:message_reads, [:message_id, :user_id])
    create index(:message_reads, [:user_id])
  end
end

defmodule Chat.Repo.Migrations.CreateMessageReactions do
  use Ecto.Migration

  def change do
    create table(:message_reactions, primary_key: false) do
      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id,    references(:users, type: :binary_id, on_delete: :delete_all),    null: false
      add :reaction,   :string, null: false, size: 64

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create primary_key(:message_reactions, [:message_id, :user_id, :reaction])
    create index(:message_reactions, [:message_id])
  end
end

defmodule Chat.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def change do
    create table(:files, primary_key: false) do
      add :id,            :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :uploader_id,   references(:users, type: :binary_id, on_delete: :nilify_all)
      add :room_id,       references(:rooms, type: :binary_id, on_delete: :nilify_all)
      add :filename,      :string, null: false
      add :original_name, :string, null: false
      add :file_type,     :string, null: false, size: 128
      add :file_size,     :bigint, null: false
      add :storage_key,   :string, null: false
      add :url,           :string, null: false
      add :thumbnail_url, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:files, [:storage_key])
    create index(:files, [:uploader_id])
    create index(:files, [:room_id])

    create constraint(:files, :positive_size,
      check: "file_size > 0 AND file_size <= 52428800")
  end
end

defmodule Chat.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id,      :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :type,    :string,  null: false, size: 64
      add :payload, :map,     null: false, default: %{}
      add :read,    :boolean, null: false, default: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notifications, [:user_id, :read, :inserted_at])
  end
end

defmodule Chat.Repo.Migrations.CreateAnalyticsEvents do
  use Ecto.Migration

  def change do
    create table(:analytics_events) do
      add :event_type,  :string,    null: false, size: 64
      add :room_id,     references(:rooms, type: :binary_id, on_delete: :nilify_all)
      add :user_id,     references(:users, type: :binary_id, on_delete: :nilify_all)
      add :payload,     :map,       null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:analytics_events, [:event_type, :inserted_at])
    create index(:analytics_events, [:room_id, :inserted_at])
  end
end

defmodule Chat.Repo.Migrations.AddPushSubscriptions do
  use Ecto.Migration

  def change do
    create table(:push_subscriptions, primary_key: false) do
      add :id,       :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id,  references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :string,  null: false
      add :p256dh,   :string,  null: false
      add :auth,     :string,  null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:push_subscriptions, [:user_id, :endpoint])
  end
end
