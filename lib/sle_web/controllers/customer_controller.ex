defmodule SLEWeb.CustomerController do
  @moduledoc """
  Handles customer endpoints.

  ## Endpoints

    * `GET /api/customers` — list customers (tenant-scoped, cursor pagination)
    * `GET /api/customers/:id` — detail with subscriptions included
  """

  use SLEWeb, :controller

  import Ecto.Query

  alias SLE.Customers
  alias SLE.Customers.Customer
  alias SLE.Pagination

  action_fallback SLEWeb.FallbackController

  @doc "GET /api/customers — list with cursor pagination."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    tenant_id = conn.assigns.tenant_id
    limit = parse_int(params["limit"], 25)
    cursor = params["cursor"]

    query =
      Customer
      |> where([c], c.tenant_id == ^tenant_id)
      |> order_by([c], asc: c.id)

    {customers, meta} = Pagination.paginate(query, cursor: cursor, limit: limit)

    json(conn, %{
      data: Enum.map(customers, &serialize_customer/1),
      meta: %{cursor: meta.cursor, hasMore: meta.has_more}
    })
  end

  @doc "GET /api/customers/:id — detail with subscriptions."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    tenant_id = conn.assigns.tenant_id

    with {:ok, customer} <-
           Customers.get(tenant_id, id, preload: [subscriptions: :plan]) do
      json(conn, %{
        customer: serialize_customer(customer),
        subscriptions: Enum.map(customer.subscriptions, &serialize_subscription/1)
      })
    end
  end

  # --- Serializers ---

  defp serialize_customer(c) do
    %{
      id: c.id,
      stripeCustomerId: c.stripe_customer_id,
      email: c.email,
      name: c.name,
      metadata: c.metadata,
      insertedAt: format_dt(c.inserted_at),
      updatedAt: format_dt(c.updated_at)
    }
  end

  defp serialize_subscription(sub) do
    %{
      id: sub.id,
      stripeSubscriptionId: sub.stripe_subscription_id,
      status: sub.status,
      currentPeriodStart: format_dt(sub.current_period_start),
      currentPeriodEnd: format_dt(sub.current_period_end),
      cancelAtPeriodEnd: sub.cancel_at_period_end,
      plan: serialize_plan(sub.plan),
      insertedAt: format_dt(sub.inserted_at),
      updatedAt: format_dt(sub.updated_at)
    }
  end

  defp serialize_plan(nil), do: nil

  defp serialize_plan(p) do
    %{
      id: p.id,
      name: p.name,
      amountCents: p.amount_cents,
      currency: p.currency,
      interval: p.interval
    }
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
