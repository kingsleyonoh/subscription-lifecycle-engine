defmodule SLEWeb.MetricsController do
  @moduledoc """
  Handles metrics API endpoints.

  ## Endpoints

    * `GET /api/metrics/overview` — latest snapshot summary
    * `GET /api/metrics/mrr` — MRR time series (?period=30d)
    * `GET /api/metrics/churn` — Churn rate time series (?period=90d)
  """

  use SLEWeb, :controller

  alias SLE.Metrics

  action_fallback SLEWeb.FallbackController

  @default_mrr_period 30
  @default_churn_period 90

  @doc "GET /api/metrics/overview — latest snapshot summary."
  @spec overview(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def overview(conn, _params) do
    tenant_id = conn.assigns.tenant_id

    with {:ok, snapshot} <- Metrics.latest(tenant_id) do
      json(conn, serialize_overview(snapshot))
    end
  end

  @doc "GET /api/metrics/mrr — MRR time series."
  @spec mrr(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def mrr(conn, params) do
    tenant_id = conn.assigns.tenant_id
    days = parse_period(params["period"], @default_mrr_period)
    snapshots = Metrics.mrr_history(tenant_id, days)

    json(conn, %{
      data: Enum.map(snapshots, &serialize_mrr_point/1)
    })
  end

  @doc "GET /api/metrics/churn — Churn rate time series."
  @spec churn(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def churn(conn, params) do
    tenant_id = conn.assigns.tenant_id
    days = parse_period(params["period"], @default_churn_period)
    snapshots = Metrics.churn_history(tenant_id, days)

    json(conn, %{
      data: Enum.map(snapshots, &serialize_churn_point/1)
    })
  end

  # --- Serializers ---

  defp serialize_overview(snapshot) do
    %{
      mrrCents: snapshot.mrr_cents,
      arrCents: snapshot.arr_cents,
      activeCount: snapshot.active_count,
      trialingCount: snapshot.trialing_count,
      churned_count: snapshot.churned_count,
      churnRate: decimal_to_string(snapshot.churn_rate),
      dunningActive: snapshot.dunning_active,
      arpuCents: snapshot.arpu_cents,
      periodStart: Date.to_iso8601(snapshot.period_start),
      periodEnd: Date.to_iso8601(snapshot.period_end),
      computedAt: format_dt(snapshot.computed_at)
    }
  end

  defp serialize_mrr_point(snapshot) do
    %{
      date: Date.to_iso8601(snapshot.period_end),
      mrrCents: snapshot.mrr_cents
    }
  end

  defp serialize_churn_point(snapshot) do
    %{
      date: Date.to_iso8601(snapshot.period_end),
      churnRate: decimal_to_string(snapshot.churn_rate)
    }
  end

  # --- Helpers ---

  defp parse_period(nil, default), do: default

  defp parse_period(period_str, default) when is_binary(period_str) do
    case Regex.run(~r/^(\d+)d$/, period_str) do
      [_, days] -> String.to_integer(days)
      _ -> default
    end
  end

  defp decimal_to_string(nil), do: "0.0000"
  defp decimal_to_string(%Decimal{} = d), do: Decimal.to_string(d)

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
