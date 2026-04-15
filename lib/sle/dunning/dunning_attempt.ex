defmodule SLE.Dunning.DunningAttempt do
  @moduledoc """
  Ecto schema for the dunning_attempts table.

  Each dunning attempt tracks a payment retry cycle for a failed invoice.
  Belongs to a tenant, subscription, invoice, and optionally a customer.
  Status transitions follow the dunning state machine:
  pending -> retrying -> retrying/recovered/exhausted -> canceled.
  Terminal states: recovered, canceled.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_statuses ~w(pending retrying recovered exhausted canceled)
  @valid_channels ~w(email telegram email_telegram)

  schema "dunning_attempts" do
    field :status, :string, default: "pending"
    field :attempt_number, :integer, default: 0
    field :max_attempts, :integer, default: 4
    field :last_attempted_at, :utc_datetime
    field :next_attempt_at, :utc_datetime
    field :recovery_amount, :integer
    field :escalation_channel, :string, default: "email"
    field :notification_payload, :map
    field :error_log, {:array, :map}, default: []

    belongs_to :tenant, SLE.Tenants.Tenant
    belongs_to :subscription, SLE.Subscriptions.Subscription
    belongs_to :invoice, SLE.Billing.Invoice
    belongs_to :customer, SLE.Customers.Customer

    timestamps()
  end

  @required_fields ~w(tenant_id subscription_id invoice_id status notification_payload)a
  @optional_fields ~w(customer_id attempt_number max_attempts last_attempted_at
    next_attempt_at recovery_amount escalation_channel error_log)a

  @doc """
  Changeset for creating or updating a dunning attempt.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(dunning_attempt, attrs) do
    dunning_attempt
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:escalation_channel, @valid_channels)
    |> unique_constraint(:invoice_id,
      name: :dunning_attempts_tenant_id_invoice_id_index,
      message: "has already been taken"
    )
    |> check_constraint(:status, name: :valid_dunning_status)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:subscription_id)
    |> foreign_key_constraint(:invoice_id)
    |> foreign_key_constraint(:customer_id)
  end
end
