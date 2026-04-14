defmodule SLE.Billing.Invoice do
  @moduledoc """
  Ecto schema for the invoices table.

  Each invoice belongs to a tenant, subscription, and customer.
  Identified by a Stripe invoice ID. The composite unique index on
  (tenant_id, stripe_invoice_id) supports multi-tenant isolation.
  Status is constrained to draft/open/paid/void/uncollectible.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_statuses ~w(draft open paid void uncollectible)

  schema "invoices" do
    field :stripe_invoice_id, :string
    field :stripe_charge_id, :string
    field :status, :string
    field :amount_due_cents, :integer
    field :amount_paid_cents, :integer, default: 0
    field :currency, :string, default: "usd"
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :due_date, :utc_datetime
    field :paid_at, :utc_datetime
    field :attempt_count, :integer, default: 0
    field :next_payment_attempt, :utc_datetime
    field :hosted_invoice_url, :string
    field :metadata, :map, default: %{}
    field :synced_to_recon, :boolean, default: false

    belongs_to :tenant, SLE.Tenants.Tenant
    belongs_to :subscription, SLE.Subscriptions.Subscription
    belongs_to :customer, SLE.Customers.Customer

    timestamps()
  end

  @required_fields ~w(tenant_id stripe_invoice_id status amount_due_cents)a
  @optional_fields ~w(subscription_id customer_id stripe_charge_id amount_paid_cents
    currency period_start period_end due_date paid_at attempt_count
    next_payment_attempt hosted_invoice_url metadata synced_to_recon)a

  @doc """
  Changeset for creating or updating an invoice.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:stripe_invoice_id, max: 255)
    |> validate_length(:stripe_charge_id, max: 255)
    |> validate_length(:currency, max: 3)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:stripe_invoice_id,
      name: :invoices_tenant_id_stripe_invoice_id_index,
      message: "has already been taken"
    )
    |> check_constraint(:status, name: :valid_invoice_status)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:subscription_id)
    |> foreign_key_constraint(:customer_id)
  end
end
