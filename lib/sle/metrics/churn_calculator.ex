defmodule SLE.Metrics.ChurnCalculator do
  @moduledoc """
  Computes churn metrics for a tenant over a given period.

  Churned subscriptions are those that transitioned to 'canceled'
  during the period (where canceled_at is between period_start and period_end).

  Churn rate = churned_count / active_count_at_period_start.
  The active_count_at_period_start comes from the most recent metrics_snapshot
  before the period. If no snapshot exists, churn_rate defaults to 0.0.
  """

  import Ecto.Query

  alias SLE.Metrics.MetricsSnapshot
  alias SLE.Repo
  alias SLE.Subscriptions.Subscription

  @doc """
  Compute churn for a tenant over a given period.

  Returns `{churned_count, churn_rate}` where churn_rate is a Decimal
  with 4 decimal places.

  ## Edge cases
  - No previous snapshot: churn_rate = 0.0000
  - Zero active at period start: churn_rate = 0.0000
  """
  @spec compute(Ecto.UUID.t(), Date.t(), Date.t()) :: {non_neg_integer(), Decimal.t()}
  def compute(tenant_id, period_start, period_end) do
    churned_count = count_churned(tenant_id, period_start, period_end)
    active_at_start = active_count_at_period_start(tenant_id, period_start)
    churn_rate = calculate_rate(churned_count, active_at_start)

    {churned_count, churn_rate}
  end

  @spec count_churned(Ecto.UUID.t(), Date.t(), Date.t()) :: non_neg_integer()
  defp count_churned(tenant_id, period_start, period_end) do
    start_dt = date_to_start_of_day(period_start)
    end_dt = date_to_end_of_day(period_end)

    Subscription
    |> where([s], s.tenant_id == ^tenant_id)
    |> where([s], s.status == "canceled")
    |> where([s], not is_nil(s.canceled_at))
    |> where([s], s.canceled_at >= ^start_dt and s.canceled_at <= ^end_dt)
    |> Repo.aggregate(:count)
  end

  @spec active_count_at_period_start(Ecto.UUID.t(), Date.t()) :: non_neg_integer() | nil
  defp active_count_at_period_start(tenant_id, period_start) do
    MetricsSnapshot
    |> where([m], m.tenant_id == ^tenant_id)
    |> where([m], m.period_end < ^period_start)
    |> order_by([m], desc: m.period_end)
    |> limit(1)
    |> select([m], m.active_count)
    |> Repo.one()
  end

  @spec calculate_rate(non_neg_integer(), non_neg_integer() | nil) :: Decimal.t()
  defp calculate_rate(_churned, nil), do: Decimal.new("0.0000")
  defp calculate_rate(_churned, 0), do: Decimal.new("0.0000")

  defp calculate_rate(churned, active) do
    Decimal.div(Decimal.new(churned), Decimal.new(active))
    |> Decimal.round(4)
  end

  defp date_to_start_of_day(date) do
    DateTime.new!(date, ~T[00:00:00Z])
  end

  defp date_to_end_of_day(date) do
    DateTime.new!(date, ~T[23:59:59Z])
  end
end
