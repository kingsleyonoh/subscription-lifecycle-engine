defmodule SLE.Metrics.ChurnCalculatorTest do
  @moduledoc false

  use SLE.DataCase, async: true

  import SLE.Factory

  alias SLE.Metrics.ChurnCalculator

  setup do
    tenant = insert(:tenant)
    customer = insert(:customer, tenant_id: tenant.id)
    plan = insert(:plan, tenant_id: tenant.id, amount_cents: 2000, interval: "month")
    {:ok, tenant: tenant, customer: customer, plan: plan}
  end

  describe "compute/3" do
    test "returns {0, 0.0} when no subscriptions exist", %{tenant: tenant} do
      period_start = ~D[2026-04-01]
      period_end = ~D[2026-04-14]

      {churned_count, churn_rate} = ChurnCalculator.compute(tenant.id, period_start, period_end)

      assert churned_count == 0
      assert Decimal.equal?(churn_rate, Decimal.new("0.0000"))
    end

    test "counts subscriptions canceled during the period", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      # Insert a previous snapshot to establish the active count at period start
      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-03-01],
        period_end: ~D[2026-03-31],
        active_count: 10,
        mrr_cents: 20_000,
        computed_at: ~U[2026-03-31 02:00:00Z]
      )

      # canceled_at within the period
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "canceled",
        canceled_at: ~U[2026-04-05 12:00:00Z]
      )

      customer2 = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer2.id,
        plan_id: plan.id,
        status: "canceled",
        canceled_at: ~U[2026-04-10 08:00:00Z]
      )

      period_start = ~D[2026-04-01]
      period_end = ~D[2026-04-14]

      {churned_count, churn_rate} = ChurnCalculator.compute(tenant.id, period_start, period_end)

      assert churned_count == 2
      # 2 / 10 = 0.2000
      assert Decimal.equal?(churn_rate, Decimal.new("0.2000"))
    end

    test "excludes subscriptions canceled outside the period", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-03-01],
        period_end: ~D[2026-03-31],
        active_count: 10,
        mrr_cents: 20_000,
        computed_at: ~U[2026-03-31 02:00:00Z]
      )

      # canceled_at BEFORE the period
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "canceled",
        canceled_at: ~U[2026-03-15 12:00:00Z]
      )

      period_start = ~D[2026-04-01]
      period_end = ~D[2026-04-14]

      {churned_count, _churn_rate} = ChurnCalculator.compute(tenant.id, period_start, period_end)

      assert churned_count == 0
    end

    test "returns churn_rate 0.0 when no previous snapshot exists", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      # No previous snapshot — should use current active count or return 0.0

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "canceled",
        canceled_at: ~U[2026-04-05 12:00:00Z]
      )

      period_start = ~D[2026-04-01]
      period_end = ~D[2026-04-14]

      {churned_count, churn_rate} = ChurnCalculator.compute(tenant.id, period_start, period_end)

      assert churned_count == 1
      # No previous snapshot → churn_rate = 0.0
      assert Decimal.equal?(churn_rate, Decimal.new("0.0000"))
    end

    test "returns churn_rate 0.0 when active_count_at_start is zero", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-03-01],
        period_end: ~D[2026-03-31],
        active_count: 0,
        mrr_cents: 0,
        computed_at: ~U[2026-03-31 02:00:00Z]
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "canceled",
        canceled_at: ~U[2026-04-05 12:00:00Z]
      )

      period_start = ~D[2026-04-01]
      period_end = ~D[2026-04-14]

      {churned_count, churn_rate} = ChurnCalculator.compute(tenant.id, period_start, period_end)

      assert churned_count == 1
      assert Decimal.equal?(churn_rate, Decimal.new("0.0000"))
    end

    test "does not count subscriptions from other tenants", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-03-01],
        period_end: ~D[2026-03-31],
        active_count: 10,
        mrr_cents: 20_000,
        computed_at: ~U[2026-03-31 02:00:00Z]
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "canceled",
        canceled_at: ~U[2026-04-05 12:00:00Z]
      )

      # Other tenant's canceled subscription
      other_tenant = insert(:tenant)
      other_customer = insert(:customer, tenant_id: other_tenant.id)

      other_plan =
        insert(:plan, tenant_id: other_tenant.id, amount_cents: 2000, interval: "month")

      insert(:subscription,
        tenant_id: other_tenant.id,
        customer_id: other_customer.id,
        plan_id: other_plan.id,
        status: "canceled",
        canceled_at: ~U[2026-04-07 12:00:00Z]
      )

      period_start = ~D[2026-04-01]
      period_end = ~D[2026-04-14]

      {churned_count, churn_rate} = ChurnCalculator.compute(tenant.id, period_start, period_end)

      assert churned_count == 1
      # 1 / 10 = 0.1000
      assert Decimal.equal?(churn_rate, Decimal.new("0.1000"))
    end

    test "uses the most recent snapshot before the period start", %{
      tenant: tenant,
      customer: customer,
      plan: plan
    } do
      # Older snapshot
      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-02-01],
        period_end: ~D[2026-02-28],
        active_count: 5,
        mrr_cents: 10_000,
        computed_at: ~U[2026-02-28 02:00:00Z]
      )

      # More recent snapshot
      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-03-01],
        period_end: ~D[2026-03-31],
        active_count: 20,
        mrr_cents: 40_000,
        computed_at: ~U[2026-03-31 02:00:00Z]
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "canceled",
        canceled_at: ~U[2026-04-05 12:00:00Z]
      )

      period_start = ~D[2026-04-01]
      period_end = ~D[2026-04-14]

      {churned_count, churn_rate} = ChurnCalculator.compute(tenant.id, period_start, period_end)

      assert churned_count == 1
      # Uses most recent snapshot active_count = 20
      # 1 / 20 = 0.0500
      assert Decimal.equal?(churn_rate, Decimal.new("0.0500"))
    end
  end
end
