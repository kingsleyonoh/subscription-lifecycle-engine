defmodule SLE.Metrics.MrrCalculator do
  @moduledoc """
  Computes Monthly Recurring Revenue (MRR) for a tenant.

  MRR = SUM of monthly-normalized plan amounts for all active subscriptions.
  - Monthly plans: amount_cents as-is
  - Yearly plans: amount_cents / 12 (integer division, rounds down)
  - Weekly plans: amount_cents * 4 (approximate monthly)
  - Subscriptions without a plan are excluded (contribute 0)
  """

  import Ecto.Query

  alias SLE.Billing.Plan
  alias SLE.Repo
  alias SLE.Subscriptions.Subscription

  @doc """
  Compute MRR in cents for a given tenant.

  Only counts subscriptions with status = 'active'.
  Returns 0 if no active subscriptions exist.
  """
  @spec compute(Ecto.UUID.t()) :: non_neg_integer()
  def compute(tenant_id) do
    Subscription
    |> where([s], s.tenant_id == ^tenant_id and s.status == "active")
    |> where([s], not is_nil(s.plan_id))
    |> join(:inner, [s], p in Plan, on: s.plan_id == p.id)
    |> select([s, p], {p.amount_cents, p.interval})
    |> Repo.all()
    |> Enum.reduce(0, fn {amount_cents, interval}, acc ->
      acc + normalize_to_monthly(amount_cents, interval)
    end)
  end

  @spec normalize_to_monthly(integer(), String.t()) :: non_neg_integer()
  defp normalize_to_monthly(amount_cents, "year"), do: div(amount_cents, 12)
  defp normalize_to_monthly(amount_cents, "week"), do: amount_cents * 4
  defp normalize_to_monthly(amount_cents, _month), do: amount_cents
end
