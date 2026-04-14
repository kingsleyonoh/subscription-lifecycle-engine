defmodule SLE.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :stripe_price_id, :string, null: false, size: 255
      add :name, :string, null: false, size: 255
      add :amount_cents, :integer, null: false
      add :currency, :string, size: 3, default: "usd", null: false
      add :interval, :string, size: 20, null: false
      add :is_active, :boolean, default: true, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plans, [:tenant_id, :stripe_price_id])
    create index(:plans, [:tenant_id, :is_active])

    create constraint(:plans, :valid_interval,
      check: "interval IN ('month', 'year', 'week')"
    )
  end
end
