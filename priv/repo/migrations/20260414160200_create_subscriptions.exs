defmodule SLE.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, type: :binary_id, on_delete: :nilify_all)
      add :stripe_subscription_id, :string, null: false, size: 255
      add :status, :string, null: false, size: 30
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :trial_start, :utc_datetime
      add :trial_end, :utc_datetime
      add :canceled_at, :utc_datetime
      add :ended_at, :utc_datetime
      add :cancel_at_period_end, :boolean, default: false, null: false
      add :trial_ending_notified, :boolean, default: false, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:tenant_id, :stripe_subscription_id])
    create index(:subscriptions, [:tenant_id, :status])
    create index(:subscriptions, [:tenant_id, :customer_id])
    create index(:subscriptions, [:tenant_id, :current_period_end])

    create index(:subscriptions, [:tenant_id, :status, :trial_end],
      where: "status = 'trialing' AND trial_ending_notified = false",
      name: :subscriptions_trial_ending_index
    )

    create constraint(:subscriptions, :valid_subscription_status,
      check:
        "status IN ('trialing', 'active', 'past_due', 'paused', 'canceled', 'unpaid', 'incomplete', 'incomplete_expired')"
    )
  end
end
