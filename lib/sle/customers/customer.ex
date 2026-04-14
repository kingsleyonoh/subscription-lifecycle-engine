defmodule SLE.Customers.Customer do
  @moduledoc """
  Ecto schema for the customers table.

  Each customer belongs to a tenant and is identified by a Stripe
  customer ID. The composite unique index on (tenant_id, stripe_customer_id)
  supports multi-tenant isolation with Stripe customer deduplication.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "customers" do
    field :stripe_customer_id, :string
    field :email, :string
    field :name, :string
    field :metadata, :map, default: %{}

    belongs_to :tenant, SLE.Tenants.Tenant
    has_many :subscriptions, SLE.Subscriptions.Subscription

    timestamps()
  end

  @required_fields ~w(tenant_id stripe_customer_id)a
  @optional_fields ~w(email name metadata)a

  @doc """
  Changeset for creating or updating a customer.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:stripe_customer_id, max: 255)
    |> validate_length(:email, max: 255)
    |> validate_length(:name, max: 255)
    |> unique_constraint(:stripe_customer_id,
      name: :customers_tenant_id_stripe_customer_id_index,
      message: "has already been taken"
    )
    |> foreign_key_constraint(:tenant_id)
  end
end
