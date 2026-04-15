defmodule SLE.Customers do
  @moduledoc """
  Context for customer management.

  Handles upserting customers from Stripe webhook data and
  tenant-scoped queries. All operations enforce tenant isolation.
  """

  import Ecto.Query

  alias SLE.Customers.Customer
  alias SLE.Repo

  @default_limit 25

  # --- Public API ---

  @doc """
  Upsert a customer from Stripe event data.

  Matches on (tenant_id, stripe_customer_id). Creates a new record
  if none exists, or updates email/name/metadata if one does.

  Expects `stripe_data` to be a map with string keys matching the
  Stripe customer object shape (id, email, name, metadata).
  """
  @spec upsert_from_stripe(Ecto.UUID.t(), map()) ::
          {:ok, Customer.t()} | {:error, Ecto.Changeset.t()}
  def upsert_from_stripe(tenant_id, stripe_data) do
    stripe_customer_id = Map.get(stripe_data, "id")

    attrs = %{
      tenant_id: tenant_id,
      stripe_customer_id: stripe_customer_id,
      email: Map.get(stripe_data, "email"),
      name: Map.get(stripe_data, "name"),
      metadata: Map.get(stripe_data, "metadata", %{})
    }

    case get_by_stripe_id(tenant_id, stripe_customer_id) do
      nil ->
        %Customer{}
        |> Customer.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Customer.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  List customers scoped by tenant_id.

  Supports offset/limit pagination via opts:
    - `:limit` — max records (default #{@default_limit})
    - `:offset` — skip N records (default 0)
  """
  @spec list(Ecto.UUID.t(), keyword()) :: [Customer.t()]
  def list(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    Customer
    |> where([c], c.tenant_id == ^tenant_id)
    |> order_by([c], asc: c.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Get a customer by UUID, scoped to tenant.

  Returns `{:ok, customer}` or `{:error, :not_found}`.

  ## Options

    - `:preload` — list of associations to preload (default [])
  """
  @spec get(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, Customer.t()} | {:error, :not_found}
  def get(tenant_id, id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    Customer
    |> where([c], c.tenant_id == ^tenant_id and c.id == ^id)
    |> preload(^preloads)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      customer -> {:ok, customer}
    end
  end

  # --- Private Helpers ---

  defp get_by_stripe_id(_tenant_id, nil), do: nil

  defp get_by_stripe_id(tenant_id, stripe_customer_id) do
    Customer
    |> where([c], c.tenant_id == ^tenant_id and c.stripe_customer_id == ^stripe_customer_id)
    |> Repo.one()
  end
end
