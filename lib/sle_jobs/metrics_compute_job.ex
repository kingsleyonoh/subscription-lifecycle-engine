defmodule SLE.Jobs.MetricsComputeJob do
  @moduledoc """
  Oban cron worker that computes daily metrics snapshots.

  Runs daily at 02:00 UTC on the `:metrics` queue. For each active
  tenant, computes MRR, churn, ARPU, dunning stats, and stores
  a metrics_snapshot record.

  Queue: `:metrics`, max attempts: 3.
  """

  use Oban.Worker, queue: :metrics, max_attempts: 3

  require Logger

  import Ecto.Query

  alias SLE.Metrics
  alias SLE.Repo
  alias SLE.Tenants.Tenant

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    list_active_tenants()
    |> Enum.each(&compute_for_tenant/1)

    :ok
  end

  defp compute_for_tenant(tenant) do
    case Metrics.compute_snapshot(tenant.id) do
      {:ok, snapshot} ->
        Logger.info(
          "MetricsComputeJob: computed snapshot for tenant #{tenant.id}, " <>
            "MRR=#{snapshot.mrr_cents}, active=#{snapshot.active_count}"
        )

      {:error, changeset} ->
        Logger.error(
          "MetricsComputeJob: failed to compute snapshot for tenant #{tenant.id}: " <>
            "#{inspect(changeset.errors)}"
        )
    end
  end

  defp list_active_tenants do
    Tenant
    |> where([t], t.is_active == true)
    |> Repo.all()
  end
end
