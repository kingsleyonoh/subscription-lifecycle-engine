defmodule SLE.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false, size: 255
      add :api_key_hash, :string, null: false, size: 255
      add :api_key_prefix, :string, null: false, size: 20
      add :stripe_config, :map, default: %{}, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:api_key_hash])
    create index(:tenants, [:api_key_prefix])
  end
end
