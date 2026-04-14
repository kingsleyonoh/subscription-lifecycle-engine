defmodule SLE.Metrics.MetricsSnapshot do
  @moduledoc """
  Ecto schema for the metrics_snapshots table.

  Stores daily MRR/churn/ARPU snapshots per tenant. Each snapshot
  covers a period defined by period_start and period_end dates.
  Tracks sync status for Client Portal integration.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "metrics_snapshots" do
    field :period_start, :date
    field :period_end, :date
    field :mrr_cents, :integer
    field :arr_cents, :integer
    field :active_count, :integer
    field :trialing_count, :integer
    field :churned_count, :integer
    field :churn_rate, :decimal
    field :dunning_active, :integer
    field :dunning_recovered_cents, :integer, default: 0
    field :arpu_cents, :integer
    field :synced_to_portal, :boolean, default: false
    field :computed_at, :utc_datetime

    belongs_to :tenant, SLE.Tenants.Tenant

    timestamps()
  end

  @required_fields ~w(tenant_id period_start period_end mrr_cents computed_at)a
  @optional_fields ~w(arr_cents active_count trialing_count churned_count churn_rate
    dunning_active dunning_recovered_cents arpu_cents synced_to_portal)a

  @doc """
  Changeset for creating or updating a metrics snapshot.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:tenant_id)
  end
end
