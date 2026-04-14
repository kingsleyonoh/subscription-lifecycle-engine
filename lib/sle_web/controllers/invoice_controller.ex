defmodule SLEWeb.InvoiceController do
  @moduledoc """
  Handles invoice endpoints.

  ## Endpoints

    * `GET /api/invoices` — list invoices (tenant-scoped, cursor pagination, filters)
    * `GET /api/invoices/:id` — invoice detail
  """

  use SLEWeb, :controller

  import Ecto.Query

  alias SLE.Billing
  alias SLE.Billing.Invoice
  alias SLE.Pagination

  action_fallback SLEWeb.FallbackController

  @doc "GET /api/invoices — list with cursor pagination and filters."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    tenant_id = conn.assigns.tenant_id
    limit = parse_int(params["limit"], 25)
    cursor = params["cursor"]

    query =
      Invoice
      |> where([i], i.tenant_id == ^tenant_id)
      |> maybe_filter(:status, params["status"])
      |> maybe_filter(:subscription_id, params["subscription_id"])
      |> maybe_filter_since(params["since"])
      |> order_by([i], asc: i.id)

    {invoices, meta} = Pagination.paginate(query, cursor: cursor, limit: limit)

    json(conn, %{
      data: Enum.map(invoices, &serialize_invoice/1),
      meta: %{cursor: meta.cursor, hasMore: meta.has_more}
    })
  end

  @doc "GET /api/invoices/:id — invoice detail."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    tenant_id = conn.assigns.tenant_id

    with {:ok, invoice} <- Billing.get_invoice(tenant_id, id) do
      json(conn, %{invoice: serialize_invoice(invoice)})
    end
  end

  # --- Serializer ---

  defp serialize_invoice(inv) do
    %{
      id: inv.id,
      stripeInvoiceId: inv.stripe_invoice_id,
      stripeChargeId: inv.stripe_charge_id,
      status: inv.status,
      amountDueCents: inv.amount_due_cents,
      amountPaidCents: inv.amount_paid_cents,
      currency: inv.currency,
      subscriptionId: inv.subscription_id,
      customerId: inv.customer_id,
      periodStart: format_dt(inv.period_start),
      periodEnd: format_dt(inv.period_end),
      dueDate: format_dt(inv.due_date),
      paidAt: format_dt(inv.paid_at),
      attemptCount: inv.attempt_count,
      nextPaymentAttempt: format_dt(inv.next_payment_attempt),
      hostedInvoiceUrl: inv.hosted_invoice_url,
      metadata: inv.metadata,
      syncedToRecon: inv.synced_to_recon,
      insertedAt: format_dt(inv.inserted_at),
      updatedAt: format_dt(inv.updated_at)
    }
  end

  # --- Helpers ---

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :status, val), do: where(query, [i], i.status == ^val)

  defp maybe_filter(query, :subscription_id, val),
    do: where(query, [i], i.subscription_id == ^val)

  defp maybe_filter_since(query, nil), do: query

  defp maybe_filter_since(query, since_str) do
    case DateTime.from_iso8601(since_str) do
      {:ok, dt, _} -> where(query, [i], i.inserted_at >= ^dt)
      _ -> query
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
