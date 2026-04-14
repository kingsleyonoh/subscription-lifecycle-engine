defmodule SLE.Repo.Migrations.CreateDunningAttempts do
  use Ecto.Migration

  def change do
    create table(:dunning_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :subscription_id, references(:subscriptions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false

      add :customer_id, references(:customers, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, size: 30, default: "pending"
      add :attempt_number, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 4
      add :last_attempted_at, :utc_datetime
      add :next_attempt_at, :utc_datetime
      add :recovery_amount, :integer
      add :escalation_channel, :string, size: 30, default: "email", null: false
      add :notification_payload, :map, null: false, default: %{}
      add :error_log, {:array, :map}, default: [], null: false

      timestamps(type: :utc_datetime)
    end

    create index(:dunning_attempts, [:tenant_id, :subscription_id, :status])
    create index(:dunning_attempts, [:tenant_id, :status, :next_attempt_at])
    create unique_index(:dunning_attempts, [:tenant_id, :invoice_id])

    create constraint(:dunning_attempts, :valid_dunning_status,
      check:
        "status IN ('pending', 'retrying', 'recovered', 'exhausted', 'canceled')"
    )
  end
end
