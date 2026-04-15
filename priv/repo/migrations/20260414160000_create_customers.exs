defmodule SLE.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :stripe_customer_id, :string, null: false, size: 255
      add :email, :string, size: 255
      add :name, :string, size: 255
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customers, [:tenant_id, :stripe_customer_id])
    create index(:customers, [:tenant_id, :email])
  end
end
