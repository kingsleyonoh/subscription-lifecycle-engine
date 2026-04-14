defmodule SLEWeb.SubscriptionController do
  @moduledoc """
  Handles subscription endpoints.

  ## Endpoints

    * `GET /api/subscriptions` — list subscriptions (tenant-scoped, cursor pagination)
    * `GET /api/subscriptions/:id` — detail with customer and plan
    * `GET /api/subscriptions/:id/events` — events timeline (paginated)
  """

  use SLEWeb, :controller

  import Ecto.Query

  alias SLE.Pagination
  alias SLE.Subscriptions
  alias SLE.Subscriptions.Subscription

  action_fallback SLEWeb.FallbackController

  @doc "GET /api/subscriptions — list with cursor pagination and filters."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    tenant_id = conn.assigns.tenant_id
    limit = parse_int(params["limit"], 25)
    cursor = params["cursor"]

    query =
      Subscription
      |> where([s], s.tenant_id == ^tenant_id)
      |> maybe_filter(:status, params["status"])
      |> maybe_filter(:customer_id, params["customer_id"])
      |> maybe_filter(:plan_id, params["plan_id"])
      |> order_by([s], asc: s.id)

    {subscriptions, meta} = Pagination.paginate(query, cursor: cursor, limit: limit)

    json(conn, %{
      data: Enum.map(subscriptions, &serialize_subscription/1),
      meta: %{cursor: meta.cursor, hasMore: meta.has_more}
    })
  end

  @doc "GET /api/subscriptions/:id — detail with customer and plan."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    tenant_id = conn.assigns.tenant_id

    with {:ok, sub} <- Subscriptions.get(tenant_id, id) do
      json(conn, %{
        subscription: serialize_subscription(sub),
        customer: serialize_customer(sub.customer),
        plan: serialize_plan(sub.plan)
      })
    end
  end

  @doc "GET /api/subscriptions/:id/events — paginated events timeline."
  @spec events(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def events(conn, %{"id" => id} = params) do
    tenant_id = conn.assigns.tenant_id
    limit = parse_int(params["limit"], 25)

    opts =
      [limit: limit]
      |> maybe_put_opt(:cursor, params["cursor"])
      |> maybe_put_opt(:event_type, params["event_type"])
      |> maybe_put_opt(:since, params["since"])

    with {:ok, events, meta} <- Subscriptions.list_events(tenant_id, id, opts) do
      json(conn, %{
        data: Enum.map(events, &serialize_event/1),
        meta: %{cursor: meta.cursor, hasMore: meta.has_more}
      })
    end
  end

  # --- Serializers ---

  defp serialize_subscription(sub) do
    %{
      id: sub.id,
      stripe_subscription_id: sub.stripe_subscription_id,
      status: sub.status,
      customer_id: sub.customer_id,
      plan_id: sub.plan_id,
      current_period_start: format_dt(sub.current_period_start),
      current_period_end: format_dt(sub.current_period_end),
      trial_start: format_dt(sub.trial_start),
      trial_end: format_dt(sub.trial_end),
      canceled_at: format_dt(sub.canceled_at),
      ended_at: format_dt(sub.ended_at),
      cancel_at_period_end: sub.cancel_at_period_end,
      metadata: sub.metadata,
      inserted_at: format_dt(sub.inserted_at),
      updated_at: format_dt(sub.updated_at)
    }
  end

  defp serialize_customer(nil), do: nil

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

  defp serialize_plan(nil), do: nil

  defp serialize_plan(p) do
    %{
      id: p.id,
      stripePriceId: p.stripe_price_id,
      name: p.name,
      amountCents: p.amount_cents,
      currency: p.currency,
      interval: p.interval,
      isActive: p.is_active,
      metadata: p.metadata,
      insertedAt: format_dt(p.inserted_at),
      updatedAt: format_dt(p.updated_at)
    }
  end

  defp serialize_event(e) do
    %{
      id: e.id,
      stripeEventId: e.stripe_event_id,
      eventType: e.event_type,
      previousStatus: e.previous_status,
      newStatus: e.new_status,
      processedAt: format_dt(e.processed_at),
      processingError: e.processing_error,
      insertedAt: format_dt(e.inserted_at)
    }
  end

  # --- Helpers ---

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :status, val), do: where(query, [s], s.status == ^val)
  defp maybe_filter(query, :customer_id, val), do: where(query, [s], s.customer_id == ^val)
  defp maybe_filter(query, :plan_id, val), do: where(query, [s], s.plan_id == ^val)

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, val), do: Keyword.put(opts, key, val)

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
