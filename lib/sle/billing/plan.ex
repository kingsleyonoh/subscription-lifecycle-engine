defmodule SLE.Billing.Plan do
  @moduledoc """
  Ecto schema for the plans table.

  Each plan belongs to a tenant and maps to a Stripe price. The
  composite unique index on (tenant_id, stripe_price_id) supports
  multi-tenant isolation. Interval is constrained to month/year/week
  via both changeset validation and a database CHECK constraint.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @valid_intervals ~w(month year week)

  schema "plans" do
    field :stripe_price_id, :string
    field :name, :string
    field :amount_cents, :integer
    field :currency, :string, default: "usd"
    field :interval, :string
    field :is_active, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :tenant, SLE.Tenants.Tenant

    timestamps()
  end

  @required_fields ~w(tenant_id stripe_price_id name amount_cents interval)a
  @optional_fields ~w(currency is_active metadata)a

  @doc """
  Changeset for creating or updating a plan.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:stripe_price_id, max: 255)
    |> validate_length(:name, max: 255)
    |> validate_length(:currency, max: 3)
    |> validate_inclusion(:interval, @valid_intervals)
    |> unique_constraint(:stripe_price_id,
      name: :plans_tenant_id_stripe_price_id_index,
      message: "has already been taken"
    )
    |> check_constraint(:interval, name: :valid_interval)
    |> foreign_key_constraint(:tenant_id)
  end
end
