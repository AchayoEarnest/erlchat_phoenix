defmodule Chat.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id,          :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name,        :string,    null: false, size: 128
      add :description, :string
      add :type,        :string,    null: false, default: "public"
      add :owner_id,    references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create constraint(:rooms, :valid_type,
      check: "type IN ('public', 'private', 'direct')")

    # Unique room name per type (except direct messages)
    create unique_index(:rooms, [:name, :type],
      name: :rooms_name_type_index,
      where: "type != 'direct'")

    create index(:rooms, [:owner_id])
    create index(:rooms, [:type])
  end
end
