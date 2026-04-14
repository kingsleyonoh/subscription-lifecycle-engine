defmodule SLE.Subscriptions.Subscription do
  @moduledoc """
  Ecto schema for the subscriptions table.

  Each subscription belongs to a tenant and customer, optionally linked
  to a plan. Status is managed via state machine transitions. The
  composite unique index on (tenant_id, stripe_subscription_id) supports
  multi-tenant isolation with Stripe subscription deduplication.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_statuses ~w(trialing active past_due paused canceled unpaid incomplete incomplete_expired)

  schema "subscriptions" do
    field :stripe_subscription_id, :string
    field :status, :string
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :trial_start, :utc_datetime
    field :trial_end, :utc_datetime
    field :canceled_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :cancel_at_period_end, :boolean, default: false
    field :trial_ending_notified, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :tenant, SLE.Tenants.Tenant
    belongs_to :customer, SLE.Customers.Customer
    belongs_to :plan, SLE.Billing.Plan

    timestamps()
  end

  @required_fields ~w(tenant_id customer_id stripe_subscription_id status)a
  @optional_fields ~w(plan_id current_period_start current_period_end
    trial_start trial_end canceled_at ended_at cancel_at_period_end
    trial_ending_notified metadata)a

  @doc """
  Changeset for creating or updating a subscription.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:stripe_subscription_id, max: 255)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:stripe_subscription_id,
      name: :subscriptions_tenant_id_stripe_subscription_id_index,
      message: "has already been taken"
    )
    |> check_constraint(:status, name: :valid_subscription_status)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:plan_id)
  end
end
