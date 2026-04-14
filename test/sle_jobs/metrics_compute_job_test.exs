defmodule SLE.Jobs.MetricsComputeJobTest do
  @moduledoc false

  use SLE.DataCase, async: false
  use Oban.Testing, repo: SLE.Repo

  import SLE.Factory

  alias SLE.Jobs.MetricsComputeJob
  alias SLE.Metrics.MetricsSnapshot

  describe "perform/1" do
    test "creates a metrics snapshot for each active tenant" do
      tenant1 = insert(:tenant, is_active: true)
      customer1 = insert(:customer, tenant_id: tenant1.id)
      plan1 = insert(:plan, tenant_id: tenant1.id, amount_cents: 3000, interval: "month")

      insert(:subscription,
        tenant_id: tenant1.id,
        customer_id: customer1.id,
        plan_id: plan1.id,
        status: "active"
      )

      tenant2 = insert(:tenant, is_active: true)
      customer2 = insert(:customer, tenant_id: tenant2.id)
      plan2 = insert(:plan, tenant_id: tenant2.id, amount_cents: 5000, interval: "month")

      insert(:subscription,
        tenant_id: tenant2.id,
        customer_id: customer2.id,
        plan_id: plan2.id,
        status: "active"
      )

      assert :ok = MetricsComputeJob.perform(%Oban.Job{args: %{}})

      snapshots = Repo.all(MetricsSnapshot)
      tenant_ids = Enum.map(snapshots, & &1.tenant_id)
      assert tenant1.id in tenant_ids
      assert tenant2.id in tenant_ids
    end

    test "skips inactive tenants" do
      inactive = insert(:tenant, is_active: false)
      active = insert(:tenant, is_active: true)

      assert :ok = MetricsComputeJob.perform(%Oban.Job{args: %{}})

      snapshots = Repo.all(MetricsSnapshot)
      tenant_ids = Enum.map(snapshots, & &1.tenant_id)
      assert active.id in tenant_ids
      refute inactive.id in tenant_ids
    end

    test "handles inactive-only tenant gracefully" do
      inactive = insert(:tenant, is_active: false)

      assert :ok = MetricsComputeJob.perform(%Oban.Job{args: %{}})

      # The inactive tenant should not have a snapshot
      refute Repo.get_by(MetricsSnapshot, tenant_id: inactive.id)
    end

    test "snapshot has correct computed fields" do
      tenant = insert(:tenant, is_active: true)
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id, amount_cents: 4000, interval: "month")

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "active"
      )

      customer2 = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer2.id,
        plan_id: plan.id,
        status: "trialing"
      )

      assert :ok = MetricsComputeJob.perform(%Oban.Job{args: %{}})

      snapshot =
        MetricsSnapshot
        |> Ecto.Query.where([m], m.tenant_id == ^tenant.id)
        |> Repo.one!()

      assert snapshot.mrr_cents == 4000
      assert snapshot.arr_cents == 48_000
      assert snapshot.active_count == 1
      assert snapshot.trialing_count == 1
      assert snapshot.arpu_cents == 4000
    end
  end
end
