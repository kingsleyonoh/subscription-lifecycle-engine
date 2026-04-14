defmodule SLE.Repo.Migrations.CreateMetricsSnapshots do
  use Ecto.Migration

  def change do
    create table(:metrics_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :mrr_cents, :integer, null: false
      add :arr_cents, :bigint
      add :active_count, :integer
      add :trialing_count, :integer
      add :churned_count, :integer
      add :churn_rate, :decimal, precision: 5, scale: 4
      add :dunning_active, :integer
      add :dunning_recovered_cents, :integer, default: 0
      add :arpu_cents, :integer
      add :synced_to_portal, :boolean, default: false, null: false
      add :computed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:metrics_snapshots, [:tenant_id, :period_end])

    create index(:metrics_snapshots, [:tenant_id, :synced_to_portal],
             where: "synced_to_portal = false",
             name: :metrics_snapshots_unsynced_index
           )
  end
end
