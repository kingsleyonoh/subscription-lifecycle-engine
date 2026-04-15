defmodule SLE.Metrics.ArpuCalculator do
  @moduledoc """
  Computes Average Revenue Per User (ARPU) for a tenant.

  ARPU = MRR / active_count (integer division).
  Returns 0 when active_count is 0 to avoid division by zero.
  """

  @doc """
  Compute ARPU in cents.

  ## Parameters
  - `mrr_cents` — Monthly Recurring Revenue in cents
  - `active_count` — Number of active subscriptions

  ## Returns
  Integer ARPU in cents (floor division).
  Returns 0 if active_count is 0.
  """
  @spec compute(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def compute(_mrr_cents, 0), do: 0
  def compute(mrr_cents, active_count), do: div(mrr_cents, active_count)
end
