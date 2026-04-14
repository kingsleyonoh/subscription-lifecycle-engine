defmodule SLE.Tenants.Tenant do
  @moduledoc """
  Ecto schema for the tenants table.

  Each tenant has a unique API key (stored as SHA-256 hash) and
  optional Stripe configuration. Multi-tenant isolation is enforced
  by scoping all queries to the authenticated tenant.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "tenants" do
    field :name, :string
    field :api_key_hash, :string
    field :api_key_prefix, :string
    field :stripe_config, :map, default: %{}
    field :is_active, :boolean, default: true

    timestamps()
  end

  @required_fields ~w(name api_key_hash api_key_prefix)a
  @optional_fields ~w(stripe_config is_active)a

  @doc """
  Changeset for creating or updating a tenant.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 255)
    |> validate_length(:api_key_hash, max: 255)
    |> validate_length(:api_key_prefix, max: 20)
    |> unique_constraint(:api_key_hash)
  end
end
