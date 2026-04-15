defmodule SLE.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :subscription_id, references(:subscriptions, type: :binary_id, on_delete: :nilify_all)
      add :customer_id, references(:customers, type: :binary_id, on_delete: :nilify_all)
      add :stripe_invoice_id, :string, null: false, size: 255
      add :stripe_charge_id, :string, size: 255
      add :status, :string, null: false, size: 30
      add :amount_due_cents, :integer, null: false
      add :amount_paid_cents, :integer, default: 0, null: false
      add :currency, :string, size: 3, default: "usd", null: false
      add :period_start, :utc_datetime
      add :period_end, :utc_datetime
      add :due_date, :utc_datetime
      add :paid_at, :utc_datetime
      add :attempt_count, :integer, default: 0, null: false
      add :next_payment_attempt, :utc_datetime
      add :hosted_invoice_url, :text
      add :metadata, :map, default: %{}, null: false
      add :synced_to_recon, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invoices, [:tenant_id, :stripe_invoice_id])
    create index(:invoices, [:tenant_id, :subscription_id])
    create index(:invoices, [:tenant_id, :status])

    create index(:invoices, [:tenant_id, :synced_to_recon],
      where: "synced_to_recon = false",
      name: :invoices_unsynced_recon_index
    )

    create constraint(:invoices, :valid_invoice_status,
      check: "status IN ('draft', 'open', 'paid', 'void', 'uncollectible')"
    )
  end
end
