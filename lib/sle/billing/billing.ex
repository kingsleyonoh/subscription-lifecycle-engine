defmodule SLE.Billing do
  @moduledoc """
  Context for billing management (plans + invoices).

  Handles plan CRUD, upsert from Stripe data, and tenant-scoped
  queries. All operations enforce tenant isolation.
  """

  import Ecto.Query

  alias SLE.Billing.Plan
  alias SLE.Repo

  @default_limit 25

  # --- Plans Public API ---

  @doc """
  Create a local plan mapping.

  Sets `tenant_id` and inserts a new plan record.
  """
  @spec create_plan(Ecto.UUID.t(), map()) ::
          {:ok, Plan.t()} | {:error, Ecto.Changeset.t()}
  def create_plan(tenant_id, attrs) do
    attrs = Map.put(attrs, :tenant_id, tenant_id)

    %Plan{}
    |> Plan.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upsert a plan by (tenant_id, stripe_price_id).

  Creates a new record if none exists, or updates name/amount_cents/
  currency/is_active/metadata if one does.
  """
  @spec upsert_plan(Ecto.UUID.t(), map()) ::
          {:ok, Plan.t()} | {:error, Ecto.Changeset.t()}
  def upsert_plan(tenant_id, attrs) do
    stripe_price_id = Map.get(attrs, :stripe_price_id) || Map.get(attrs, "stripe_price_id")

    case get_plan_by_stripe_price_id(tenant_id, stripe_price_id) do
      nil ->
        create_plan(tenant_id, attrs)

      existing ->
        existing
        |> Plan.changeset(Map.put(attrs, :tenant_id, tenant_id))
        |> Repo.update()
    end
  end

  @doc """
  List plans scoped by tenant_id.

  By default returns only active plans. Options:
    - `:include_inactive` — when true, returns all plans
    - `:limit` — max records (default #{@default_limit})
    - `:offset` — skip N records (default 0)
  """
  @spec list_plans(Ecto.UUID.t(), keyword()) :: [Plan.t()]
  def list_plans(tenant_id, opts \\ []) do
    include_inactive = Keyword.get(opts, :include_inactive, false)
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    Plan
    |> where([p], p.tenant_id == ^tenant_id)
    |> maybe_filter_active(include_inactive)
    |> order_by([p], asc: p.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Get a plan by UUID, scoped to tenant.

  Returns `{:ok, plan}` or `{:error, :not_found}`.
  """
  @spec get_plan(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Plan.t()} | {:error, :not_found}
  def get_plan(tenant_id, id) do
    Plan
    |> where([p], p.tenant_id == ^tenant_id and p.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  @doc """
  Update a plan's name or is_active status.

  Returns `{:ok, plan}`, `{:error, changeset}`, or `{:error, :not_found}`.
  """
  @spec update_plan(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Plan.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  def update_plan(tenant_id, id, attrs) do
    case get_plan(tenant_id, id) do
      {:ok, plan} ->
        plan
        |> Plan.changeset(Map.put(attrs, :tenant_id, tenant_id))
        |> Repo.update()

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # --- Private Helpers ---

  defp get_plan_by_stripe_price_id(tenant_id, stripe_price_id) do
    Plan
    |> where([p], p.tenant_id == ^tenant_id and p.stripe_price_id == ^stripe_price_id)
    |> Repo.one()
  end

  defp maybe_filter_active(query, true), do: query
  defp maybe_filter_active(query, false), do: where(query, [p], p.is_active == true)
end
