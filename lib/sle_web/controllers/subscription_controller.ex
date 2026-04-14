defmodule SLEWeb.SubscriptionController do
  @moduledoc """
  Handles subscription list endpoint.

  ## Endpoints

    * `GET /api/subscriptions` — list subscriptions (tenant-scoped, cursor pagination)
  """

  use SLEWeb, :controller

  import Ecto.Query

  alias SLE.Pagination
  alias SLE.Subscriptions.Subscription

  action_fallback SLEWeb.FallbackController

  @doc """
  GET /api/subscriptions

  Lists subscriptions for the authenticated tenant with cursor pagination.

  ## Query Parameters

    - `status` — filter by subscription status
    - `customer_id` — filter by customer UUID
    - `plan_id` — filter by plan UUID
    - `cursor` — Base64-encoded cursor from previous page
    - `limit` — records per page (default 25, max 100)
  """
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
      data: Enum.map(subscriptions, &serialize/1),
      meta: %{
        cursor: meta.cursor,
        hasMore: meta.has_more
      }
    })
  end

  # --- Private Helpers ---

  defp serialize(sub) do
    %{
      id: sub.id,
      stripe_subscription_id: sub.stripe_subscription_id,
      status: sub.status,
      customer_id: sub.customer_id,
      plan_id: sub.plan_id,
      current_period_start: format_datetime(sub.current_period_start),
      current_period_end: format_datetime(sub.current_period_end),
      trial_start: format_datetime(sub.trial_start),
      trial_end: format_datetime(sub.trial_end),
      canceled_at: format_datetime(sub.canceled_at),
      ended_at: format_datetime(sub.ended_at),
      cancel_at_period_end: sub.cancel_at_period_end,
      metadata: sub.metadata,
      inserted_at: format_datetime(sub.inserted_at),
      updated_at: format_datetime(sub.updated_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :status, val), do: where(query, [s], s.status == ^val)
  defp maybe_filter(query, :customer_id, val), do: where(query, [s], s.customer_id == ^val)
  defp maybe_filter(query, :plan_id, val), do: where(query, [s], s.plan_id == ^val)

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
