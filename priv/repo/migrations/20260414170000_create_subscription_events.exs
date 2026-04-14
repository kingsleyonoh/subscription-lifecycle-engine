defmodule SLE.Repo.Migrations.CreateSubscriptionEvents do
  use Ecto.Migration

  def change do
    create table(:subscription_events, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subscription_id, references(:subscriptions, type: :binary_id, on_delete: :nilify_all)
      add :stripe_event_id, :string, null: false
      add :event_type, :string, null: false, size: 100
      add :previous_status, :string, size: 30
      add :new_status, :string, size: 30
      add :payload, :map, null: false, default: %{}
      add :processed_at, :utc_datetime
      add :processing_error, :text
      add :idempotency_key, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscription_events, [:tenant_id, :idempotency_key])
    create index(:subscription_events, [:tenant_id, :subscription_id, :inserted_at])
    create index(:subscription_events, [:tenant_id, :event_type])

    create index(:subscription_events, [:processed_at],
      where: "processed_at IS NULL",
      name: :subscription_events_unprocessed_index
    )
  end
end
