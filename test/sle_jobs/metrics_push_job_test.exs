defmodule SLE.Jobs.MetricsPushJobTest do
  @moduledoc false

  use SLE.DataCase, async: false
  use Oban.Testing, repo: SLE.Repo

  import Mox
  import SLE.Factory

  alias SLE.Jobs.MetricsPushJob
  alias SLE.Metrics.MetricsSnapshot

  setup :verify_on_exit!

  describe "perform/1" do
    test "pushes unsynced snapshots to client portal" do
      Application.put_env(:sle, :client_portal_enabled, true)
      Application.put_env(:sle, :client_portal_client, SLE.Ecosystem.ClientPortalMock)

      on_exit(fn ->
        Application.put_env(:sle, :client_portal_enabled, false)
      end)

      tenant = insert(:tenant)

      snapshot =
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          mrr_cents: 100_000,
          arr_cents: 1_200_000,
          active_count: 50,
          trialing_count: 5,
          churned_count: 2,
          churn_rate: Decimal.new("0.0385"),
          arpu_cents: 2000,
          synced_to_portal: false
        )

      expect(SLE.Ecosystem.ClientPortalMock, :push_metrics, fn metrics ->
        assert metrics.mrr_cents == 100_000
        assert metrics.arr_cents == 1_200_000
        assert metrics.active_count == 50
        assert metrics.trialing_count == 5
        assert metrics.churned_count == 2
        assert metrics.arpu_cents == 2000
        :ok
      end)

      assert :ok = MetricsPushJob.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(MetricsSnapshot, snapshot.id)
      assert updated.synced_to_portal == true
    end

    test "skips already-synced snapshots" do
      Application.put_env(:sle, :client_portal_enabled, true)
      Application.put_env(:sle, :client_portal_client, SLE.Ecosystem.ClientPortalMock)

      on_exit(fn ->
        Application.put_env(:sle, :client_portal_enabled, false)
      end)

      tenant = insert(:tenant)

      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        synced_to_portal: true
      )

      # No mock expectation — push_metrics should not be called
      assert :ok = MetricsPushJob.perform(%Oban.Job{args: %{}})
    end

    test "leaves synced_to_portal as false when push fails" do
      Application.put_env(:sle, :client_portal_enabled, true)
      Application.put_env(:sle, :client_portal_client, SLE.Ecosystem.ClientPortalMock)

      on_exit(fn ->
        Application.put_env(:sle, :client_portal_enabled, false)
      end)

      tenant = insert(:tenant)

      snapshot =
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          synced_to_portal: false
        )

      expect(SLE.Ecosystem.ClientPortalMock, :push_metrics, fn _metrics ->
        {:error, :connection_refused}
      end)

      assert :ok = MetricsPushJob.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(MetricsSnapshot, snapshot.id)
      assert updated.synced_to_portal == false
    end

    test "returns :ok when client portal is disabled" do
      Application.put_env(:sle, :client_portal_enabled, false)

      tenant = insert(:tenant)

      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        synced_to_portal: false
      )

      # No mock expectation — should not be called
      assert :ok = MetricsPushJob.perform(%Oban.Job{args: %{}})
    end

    test "handles multiple snapshots" do
      Application.put_env(:sle, :client_portal_enabled, true)
      Application.put_env(:sle, :client_portal_client, SLE.Ecosystem.ClientPortalMock)

      on_exit(fn ->
        Application.put_env(:sle, :client_portal_enabled, false)
      end)

      tenant = insert(:tenant)

      snap1 =
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          period_start: ~D[2026-04-01],
          period_end: ~D[2026-04-02],
          mrr_cents: 50_000,
          synced_to_portal: false
        )

      snap2 =
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          period_start: ~D[2026-04-02],
          period_end: ~D[2026-04-03],
          mrr_cents: 55_000,
          synced_to_portal: false
        )

      expect(SLE.Ecosystem.ClientPortalMock, :push_metrics, 2, fn _metrics ->
        :ok
      end)

      assert :ok = MetricsPushJob.perform(%Oban.Job{args: %{}})

      assert Repo.get!(MetricsSnapshot, snap1.id).synced_to_portal == true
      assert Repo.get!(MetricsSnapshot, snap2.id).synced_to_portal == true
    end

    test "returns :ok when there are no unsynced snapshots" do
      Application.put_env(:sle, :client_portal_enabled, true)
      Application.put_env(:sle, :client_portal_client, SLE.Ecosystem.ClientPortalMock)

      on_exit(fn ->
        Application.put_env(:sle, :client_portal_enabled, false)
      end)

      # No snapshots at all
      assert :ok = MetricsPushJob.perform(%Oban.Job{args: %{}})
    end

    test "pushes snapshots from multiple tenants" do
      Application.put_env(:sle, :client_portal_enabled, true)
      Application.put_env(:sle, :client_portal_client, SLE.Ecosystem.ClientPortalMock)

      on_exit(fn ->
        Application.put_env(:sle, :client_portal_enabled, false)
      end)

      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)

      snap1 =
        insert(:metrics_snapshot,
          tenant_id: tenant1.id,
          mrr_cents: 10_000,
          synced_to_portal: false
        )

      snap2 =
        insert(:metrics_snapshot,
          tenant_id: tenant2.id,
          mrr_cents: 20_000,
          synced_to_portal: false
        )

      expect(SLE.Ecosystem.ClientPortalMock, :push_metrics, 2, fn _metrics ->
        :ok
      end)

      assert :ok = MetricsPushJob.perform(%Oban.Job{args: %{}})

      assert Repo.get!(MetricsSnapshot, snap1.id).synced_to_portal == true
      assert Repo.get!(MetricsSnapshot, snap2.id).synced_to_portal == true
    end
  end
end
