defmodule SLE.Jobs.MetricsPushJob do
  @moduledoc """
  Oban cron worker that pushes metrics snapshots to the Client Portal.

  Runs daily at 03:00 UTC on the `:ecosystem` queue. Finds all
  metrics snapshots with `synced_to_portal = false`, pushes each
  via `SLE.Ecosystem.push_metrics/1`.

  On success: marks snapshot `synced_to_portal = true`.
  On failure: leaves `synced_to_portal = false` (retry next cycle).

  Queue: `:ecosystem`, max attempts: 3.
  """

  use Oban.Worker, queue: :ecosystem, max_attempts: 3

  require Logger

  import Ecto.Query

  alias SLE.Ecosystem
  alias SLE.Metrics.MetricsSnapshot
  alias SLE.Repo

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    snapshots = fetch_unsynced_snapshots()

    if Enum.empty?(snapshots) do
      Logger.info("MetricsPushJob: no unsynced snapshots to push")
      :ok
    else
      push_all(snapshots)
    end
  end

  defp fetch_unsynced_snapshots do
    MetricsSnapshot
    |> where([m], m.synced_to_portal == false)
    |> order_by([m], asc: m.period_end)
    |> Repo.all()
  end

  defp push_all(snapshots) do
    Enum.each(snapshots, &push_snapshot/1)
    :ok
  end

  defp push_snapshot(snapshot) do
    metrics = build_metrics_payload(snapshot)

    case Ecosystem.push_metrics(metrics) do
      :ok ->
        mark_synced(snapshot)
        Logger.info("MetricsPushJob: pushed snapshot #{snapshot.id}")

      {:error, reason} ->
        Logger.warning(
          "MetricsPushJob: push failed for #{snapshot.id}: #{inspect(reason)}, " <>
            "will retry next cycle"
        )
    end
  end

  defp build_metrics_payload(snapshot) do
    %{
      tenant_id: snapshot.tenant_id,
      period_start: Date.to_iso8601(snapshot.period_start),
      period_end: Date.to_iso8601(snapshot.period_end),
      mrr_cents: snapshot.mrr_cents,
      arr_cents: snapshot.arr_cents,
      active_count: snapshot.active_count,
      trialing_count: snapshot.trialing_count,
      churned_count: snapshot.churned_count,
      churn_rate: snapshot.churn_rate,
      arpu_cents: snapshot.arpu_cents,
      dunning_active: snapshot.dunning_active,
      dunning_recovered_cents: snapshot.dunning_recovered_cents,
      computed_at: DateTime.to_iso8601(snapshot.computed_at)
    }
  end

  defp mark_synced(snapshot) do
    MetricsSnapshot
    |> where([m], m.id == ^snapshot.id)
    |> Repo.update_all(set: [synced_to_portal: true])
  end
end
