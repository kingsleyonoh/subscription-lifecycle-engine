defmodule SLE.Metrics.MetricsTest do
  @moduledoc false

  use SLE.DataCase, async: true

  import SLE.Factory

  alias SLE.Metrics

  setup do
    tenant = insert(:tenant)
    customer = insert(:customer, tenant_id: tenant.id)
    plan = insert(:plan, tenant_id: tenant.id, amount_cents: 2000, interval: "month")
    {:ok, tenant: tenant, customer: customer, plan: plan}
  end

  describe "compute_snapshot/1" do
    test "creates a snapshot for tenant with active subscriptions", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "active"
      )

      assert {:ok, snapshot} = Metrics.compute_snapshot(tenant.id)
      assert snapshot.tenant_id == tenant.id
      assert snapshot.mrr_cents == 2000
      assert snapshot.arr_cents == 24_000
      assert snapshot.active_count == 1
      assert snapshot.arpu_cents == 2000
      assert snapshot.period_start != nil
      assert snapshot.period_end != nil
      assert snapshot.computed_at != nil
    end

    test "creates all-zeroes snapshot when no subscriptions", %{tenant: tenant} do
      assert {:ok, snapshot} = Metrics.compute_snapshot(tenant.id)
      assert snapshot.mrr_cents == 0
      assert snapshot.arr_cents == 0
      assert snapshot.active_count == 0
      assert snapshot.trialing_count == 0
      assert snapshot.churned_count == 0
      assert Decimal.equal?(snapshot.churn_rate, Decimal.new("0.0000"))
      assert snapshot.arpu_cents == 0
    end

    test "counts trialing subscriptions separately", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "trialing"
      )

      assert {:ok, snapshot} = Metrics.compute_snapshot(tenant.id)
      assert snapshot.trialing_count == 1
      assert snapshot.active_count == 0
    end

    test "includes dunning_active count", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          status: "past_due"
        )

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        invoice_id: invoice.id,
        customer_id: customer.id,
        status: "retrying",
        notification_payload: %{}
      )

      assert {:ok, snapshot} = Metrics.compute_snapshot(tenant.id)
      assert snapshot.dunning_active == 1
    end

    test "includes dunning_recovered_cents for the period", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          status: "active"
        )

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "paid"
        )

      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        invoice_id: invoice.id,
        customer_id: customer.id,
        status: "recovered",
        recovery_amount: 5000,
        notification_payload: %{}
      )

      assert {:ok, snapshot} = Metrics.compute_snapshot(tenant.id)
      assert snapshot.dunning_recovered_cents == 5000
    end
  end

  describe "latest/1" do
    test "returns the most recent snapshot for tenant", %{tenant: tenant} do
      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-04-07],
        mrr_cents: 10_000,
        computed_at: ~U[2026-04-07 02:00:00Z]
      )

      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-04-08],
        period_end: ~D[2026-04-14],
        mrr_cents: 12_000,
        computed_at: ~U[2026-04-14 02:00:00Z]
      )

      assert {:ok, snapshot} = Metrics.latest(tenant.id)
      assert snapshot.mrr_cents == 12_000
    end

    test "returns {:error, :not_found} when no snapshots exist", %{tenant: tenant} do
      assert {:error, :not_found} = Metrics.latest(tenant.id)
    end

    test "does not return snapshots from other tenants", %{tenant: tenant} do
      other_tenant = insert(:tenant)

      insert(:metrics_snapshot,
        tenant_id: other_tenant.id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-04-14],
        mrr_cents: 50_000,
        computed_at: ~U[2026-04-14 02:00:00Z]
      )

      assert {:error, :not_found} = Metrics.latest(tenant.id)
    end
  end

  describe "mrr_history/2" do
    test "returns snapshots within the given day range", %{tenant: tenant} do
      today = Date.utc_today()

      # Create 6 snapshots with period_end from today to 5 days ago
      for i <- 0..5 do
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          period_start: Date.add(today, -(i + 1)),
          period_end: Date.add(today, -i),
          mrr_cents: 10_000 + i * 1000,
          computed_at:
            DateTime.new!(Date.add(today, -i), ~T[02:00:00Z]) |> DateTime.truncate(:second)
        )
      end

      # With 3 days, cutoff = today - 3. Snapshots with period_end > cutoff
      # means period_end in {today, today-1, today-2} = 3 snapshots
      snapshots = Metrics.mrr_history(tenant.id, 3)
      assert length(snapshots) == 3
    end

    test "returns empty list when no snapshots exist", %{tenant: tenant} do
      assert Metrics.mrr_history(tenant.id, 30) == []
    end

    test "only returns snapshots for the given tenant", %{tenant: tenant} do
      other_tenant = insert(:tenant)
      today = Date.utc_today()

      insert(:metrics_snapshot,
        tenant_id: other_tenant.id,
        period_start: Date.add(today, -1),
        period_end: today,
        mrr_cents: 50_000,
        computed_at: DateTime.new!(today, ~T[02:00:00Z]) |> DateTime.truncate(:second)
      )

      assert Metrics.mrr_history(tenant.id, 30) == []
    end
  end

  describe "churn_history/2" do
    test "returns snapshots within the given day range", %{tenant: tenant} do
      today = Date.utc_today()

      for i <- 0..5 do
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          period_start: Date.add(today, -(i + 1)),
          period_end: Date.add(today, -i),
          mrr_cents: 10_000,
          churn_rate: Decimal.new("0.0500"),
          computed_at:
            DateTime.new!(Date.add(today, -i), ~T[02:00:00Z]) |> DateTime.truncate(:second)
        )
      end

      snapshots = Metrics.churn_history(tenant.id, 3)
      assert length(snapshots) == 3
    end

    test "returns empty list when no snapshots", %{tenant: tenant} do
      assert Metrics.churn_history(tenant.id, 90) == []
    end
  end
end
