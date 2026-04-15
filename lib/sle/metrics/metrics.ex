defmodule SLE.Metrics do
  @moduledoc """
  Context for metrics computation and retrieval.

  Orchestrates MRR, churn, and ARPU calculators to produce daily
  snapshots. Provides query functions for the metrics API.
  """

  import Ecto.Query

  alias SLE.Dunning.DunningAttempt
  alias SLE.Metrics.{ArpuCalculator, ChurnCalculator, MetricsSnapshot, MrrCalculator}
  alias SLE.Repo
  alias SLE.Subscriptions.Subscription

  # --- Snapshot Computation ---

  @doc """
  Compute and store a metrics snapshot for a tenant.

  Orchestrates all calculators:
  1. MRR via MrrCalculator
  2. Active/trialing subscription counts
  3. Churn via ChurnCalculator (yesterday = period)
  4. ARPU via ArpuCalculator
  5. Active dunning attempts count
  6. Dunning recovered cents for the period

  Returns `{:ok, snapshot}` or `{:error, changeset}`.
  """
  @spec compute_snapshot(Ecto.UUID.t()) ::
          {:ok, MetricsSnapshot.t()} | {:error, Ecto.Changeset.t()}
  def compute_snapshot(tenant_id) do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    mrr_cents = MrrCalculator.compute(tenant_id)
    arr_cents = mrr_cents * 12
    active_count = count_by_status(tenant_id, "active")
    trialing_count = count_by_status(tenant_id, "trialing")
    {churned_count, churn_rate} = ChurnCalculator.compute(tenant_id, yesterday, today)
    arpu_cents = ArpuCalculator.compute(mrr_cents, active_count)
    dunning_active = count_active_dunning(tenant_id)
    recovered_cents = sum_recovered_cents(tenant_id, yesterday, today)

    attrs = %{
      tenant_id: tenant_id,
      period_start: yesterday,
      period_end: today,
      mrr_cents: mrr_cents,
      arr_cents: arr_cents,
      active_count: active_count,
      trialing_count: trialing_count,
      churned_count: churned_count,
      churn_rate: churn_rate,
      arpu_cents: arpu_cents,
      dunning_active: dunning_active,
      dunning_recovered_cents: recovered_cents,
      computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %MetricsSnapshot{}
    |> MetricsSnapshot.changeset(attrs)
    |> Repo.insert()
  end

  # --- Query Functions ---

  @doc """
  Get the most recent metrics snapshot for a tenant.

  Returns `{:ok, snapshot}` or `{:error, :not_found}`.
  """
  @spec latest(Ecto.UUID.t()) ::
          {:ok, MetricsSnapshot.t()} | {:error, :not_found}
  def latest(tenant_id) do
    MetricsSnapshot
    |> where([m], m.tenant_id == ^tenant_id)
    |> order_by([m], desc: m.period_end)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      snapshot -> {:ok, snapshot}
    end
  end

  @doc """
  Get MRR history for a tenant over the given number of days.

  Returns a list of snapshots ordered by period_end ascending.
  """
  @spec mrr_history(Ecto.UUID.t(), pos_integer()) :: [MetricsSnapshot.t()]
  def mrr_history(tenant_id, days) do
    cutoff = Date.add(Date.utc_today(), -days)

    MetricsSnapshot
    |> where([m], m.tenant_id == ^tenant_id)
    |> where([m], m.period_end > ^cutoff)
    |> order_by([m], asc: m.period_end)
    |> Repo.all()
  end

  @doc """
  Get churn rate history for a tenant over the given number of days.

  Returns a list of snapshots ordered by period_end ascending.
  """
  @spec churn_history(Ecto.UUID.t(), pos_integer()) :: [MetricsSnapshot.t()]
  def churn_history(tenant_id, days) do
    cutoff = Date.add(Date.utc_today(), -days)

    MetricsSnapshot
    |> where([m], m.tenant_id == ^tenant_id)
    |> where([m], m.period_end > ^cutoff)
    |> order_by([m], asc: m.period_end)
    |> Repo.all()
  end

  # --- Private Helpers ---

  defp count_by_status(tenant_id, status) do
    Subscription
    |> where([s], s.tenant_id == ^tenant_id and s.status == ^status)
    |> Repo.aggregate(:count)
  end

  defp count_active_dunning(tenant_id) do
    DunningAttempt
    |> where([d], d.tenant_id == ^tenant_id)
    |> where([d], d.status in ["pending", "retrying"])
    |> Repo.aggregate(:count)
  end

  defp sum_recovered_cents(tenant_id, period_start, period_end) do
    start_dt = DateTime.new!(period_start, ~T[00:00:00Z])
    end_dt = DateTime.new!(period_end, ~T[23:59:59Z])

    DunningAttempt
    |> where([d], d.tenant_id == ^tenant_id)
    |> where([d], d.status == "recovered")
    |> where([d], d.updated_at >= ^start_dt and d.updated_at <= ^end_dt)
    |> Repo.aggregate(:sum, :recovery_amount) || 0
  end
end
