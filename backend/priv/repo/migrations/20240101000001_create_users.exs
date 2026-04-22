defmodule Chat.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id,            :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :username,      :string,    null: false, size: 64
      add :email,         :string,    null: false, size: 256
      add :password_hash, :string,    null: false
      add :role,          :string,    null: false, default: "user"
      add :avatar,        :string
      add :status,        :string,    null: false, default: "offline"
      add :last_seen,     :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])
    create index(:users, [:status])

    # Enforce valid roles at DB level
    create constraint(:users, :valid_role,
      check: "role IN ('admin', 'moderator', 'user')")
    create constraint(:users, :valid_status,
      check: "status IN ('online', 'offline', 'away')")
  end
end
