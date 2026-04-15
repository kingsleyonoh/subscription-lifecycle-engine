defmodule SLE.Subscriptions.SubscriptionEvent do
  @moduledoc """
  Ecto schema for the subscription_events table.

  Stores immutable event records from Stripe webhook delivery.
  Each event belongs to a tenant and optionally to a subscription.
  The idempotency_key (tenant_id:stripe_event_id) prevents
  duplicate processing.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "subscription_events" do
    field :stripe_event_id, :string
    field :event_type, :string
    field :previous_status, :string
    field :new_status, :string
    field :payload, :map, default: %{}
    field :processed_at, :utc_datetime
    field :processing_error, :string
    field :idempotency_key, :string

    belongs_to :tenant, SLE.Tenants.Tenant
    belongs_to :subscription, SLE.Subscriptions.Subscription

    timestamps()
  end

  @required_fields ~w(tenant_id stripe_event_id event_type payload idempotency_key)a
  @optional_fields ~w(subscription_id previous_status new_status processed_at processing_error)a

  @doc """
  Changeset for creating or updating a subscription event.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:event_type, max: 100)
    |> validate_length(:previous_status, max: 30)
    |> validate_length(:new_status, max: 30)
    |> unique_constraint(:idempotency_key,
      name: :subscription_events_tenant_id_idempotency_key_index,
      message: "has already been taken"
    )
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:subscription_id)
  end
end
