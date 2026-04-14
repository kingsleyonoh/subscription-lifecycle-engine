defmodule SLE.Billing do
  @moduledoc """
  Context for billing management (plans + invoices).

  Handles plan CRUD, invoice upsert from Stripe data, and
  tenant-scoped queries. All operations enforce tenant isolation.
  """

  import Ecto.Query

  alias SLE.Billing.{Invoice, Plan}
  alias SLE.Customers.Customer
  alias SLE.Repo
  alias SLE.Subscriptions.Subscription

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

  # --- Invoices Public API ---

  @doc """
  Upsert an invoice from Stripe webhook data.

  Matches on (tenant_id, stripe_invoice_id). Creates a new record
  if none exists, or updates status/amounts/dates if one does.
  Resolves subscription_id and customer_id from Stripe IDs.
  """
  @spec upsert_invoice(Ecto.UUID.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def upsert_invoice(tenant_id, stripe_data) do
    stripe_invoice_id = Map.get(stripe_data, "id")
    attrs = build_invoice_attrs(tenant_id, stripe_data)

    case get_invoice_by_stripe_id(tenant_id, stripe_invoice_id) do
      nil ->
        %Invoice{}
        |> Invoice.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Invoice.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  List invoices scoped by tenant_id.

  Supports filtering by status, subscription_id and
  offset/limit pagination.
  """
  @spec list_invoices(Ecto.UUID.t(), keyword()) :: [Invoice.t()]
  def list_invoices(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    Invoice
    |> where([i], i.tenant_id == ^tenant_id)
    |> maybe_filter_invoice_status(opts)
    |> maybe_filter_subscription(opts)
    |> order_by([i], asc: i.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Get an invoice by UUID, scoped to tenant.

  Returns `{:ok, invoice}` or `{:error, :not_found}`.
  """
  @spec get_invoice(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Invoice.t()} | {:error, :not_found}
  def get_invoice(tenant_id, id) do
    Invoice
    |> where([i], i.tenant_id == ^tenant_id and i.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      invoice -> {:ok, invoice}
    end
  end

  # --- Private Helpers ---

  defp get_plan_by_stripe_price_id(_tenant_id, nil), do: nil

  defp get_plan_by_stripe_price_id(tenant_id, stripe_price_id) do
    Plan
    |> where([p], p.tenant_id == ^tenant_id and p.stripe_price_id == ^stripe_price_id)
    |> Repo.one()
  end

  defp maybe_filter_active(query, true), do: query
  defp maybe_filter_active(query, false), do: where(query, [p], p.is_active == true)

  defp get_invoice_by_stripe_id(_tenant_id, nil), do: nil

  defp get_invoice_by_stripe_id(tenant_id, stripe_invoice_id) do
    Invoice
    |> where([i], i.tenant_id == ^tenant_id and i.stripe_invoice_id == ^stripe_invoice_id)
    |> Repo.one()
  end

  defp build_invoice_attrs(tenant_id, data) do
    subscription_id = resolve_subscription_id(tenant_id, Map.get(data, "subscription"))
    customer_id = resolve_customer_id(tenant_id, Map.get(data, "customer"))

    %{
      tenant_id: tenant_id,
      subscription_id: subscription_id,
      customer_id: customer_id,
      stripe_invoice_id: Map.get(data, "id"),
      stripe_charge_id: Map.get(data, "charge"),
      status: Map.get(data, "status"),
      amount_due_cents: Map.get(data, "amount_due"),
      amount_paid_cents: Map.get(data, "amount_paid", 0),
      currency: Map.get(data, "currency", "usd"),
      period_start: parse_timestamp(Map.get(data, "period_start")),
      period_end: parse_timestamp(Map.get(data, "period_end")),
      due_date: parse_timestamp(Map.get(data, "due_date")),
      paid_at: parse_timestamp(Map.get(data, "paid_at")),
      attempt_count: Map.get(data, "attempt_count", 0),
      next_payment_attempt: parse_timestamp(Map.get(data, "next_payment_attempt")),
      hosted_invoice_url: Map.get(data, "hosted_invoice_url"),
      metadata: Map.get(data, "metadata", %{})
    }
  end

  defp resolve_subscription_id(_tenant_id, nil), do: nil

  defp resolve_subscription_id(tenant_id, stripe_sub_id) do
    Subscription
    |> where([s], s.tenant_id == ^tenant_id and s.stripe_subscription_id == ^stripe_sub_id)
    |> select([s], s.id)
    |> Repo.one()
  end

  defp resolve_customer_id(_tenant_id, nil), do: nil

  defp resolve_customer_id(tenant_id, stripe_customer_id) do
    Customer
    |> where([c], c.tenant_id == ^tenant_id and c.stripe_customer_id == ^stripe_customer_id)
    |> select([c], c.id)
    |> Repo.one()
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(ts) when is_integer(ts) do
    DateTime.from_unix!(ts) |> DateTime.truncate(:second)
  end

  defp parse_timestamp(%DateTime{} = dt), do: dt

  defp maybe_filter_invoice_status(query, opts) do
    case Keyword.get(opts, :status) do
      nil -> query
      status -> where(query, [i], i.status == ^status)
    end
  end

  defp maybe_filter_subscription(query, opts) do
    case Keyword.get(opts, :subscription_id) do
      nil -> query
      sub_id -> where(query, [i], i.subscription_id == ^sub_id)
    end
  end
end
