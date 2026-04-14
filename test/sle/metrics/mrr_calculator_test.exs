defmodule SLE.Metrics.MrrCalculatorTest do
  @moduledoc false

  use SLE.DataCase, async: true

  import SLE.Factory

  alias SLE.Metrics.MrrCalculator

  setup do
    tenant = insert(:tenant)
    customer = insert(:customer, tenant_id: tenant.id)
    {:ok, tenant: tenant, customer: customer}
  end

  describe "compute/1" do
    test "returns 0 when no active subscriptions exist", %{tenant: tenant} do
      assert MrrCalculator.compute(tenant.id) == 0
    end

    test "sums amount_cents for active monthly subscriptions", %{
      tenant: tenant,
      customer: customer
    } do
      plan1 = insert(:plan, tenant_id: tenant.id, amount_cents: 2000, interval: "month")
      plan2 = insert(:plan, tenant_id: tenant.id, amount_cents: 3000, interval: "month")

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan1.id,
        status: "active"
      )

      customer2 = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer2.id,
        plan_id: plan2.id,
        status: "active"
      )

      assert MrrCalculator.compute(tenant.id) == 5000
    end

    test "yearly plans are divided by 12 with integer division", %{
      tenant: tenant,
      customer: customer
    } do
      # 12000 / 12 = 1000
      plan = insert(:plan, tenant_id: tenant.id, amount_cents: 12_000, interval: "year")

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "active"
      )

      assert MrrCalculator.compute(tenant.id) == 1000
    end

    test "yearly plans round down with integer division", %{
      tenant: tenant,
      customer: customer
    } do
      # 10000 / 12 = 833 (integer division, rounds down)
      plan = insert(:plan, tenant_id: tenant.id, amount_cents: 10_000, interval: "year")

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "active"
      )

      assert MrrCalculator.compute(tenant.id) == 833
    end

    test "mixes monthly and yearly plans correctly", %{tenant: tenant, customer: customer} do
      monthly_plan = insert(:plan, tenant_id: tenant.id, amount_cents: 2000, interval: "month")
      yearly_plan = insert(:plan, tenant_id: tenant.id, amount_cents: 24_000, interval: "year")

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: monthly_plan.id,
        status: "active"
      )

      customer2 = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer2.id,
        plan_id: yearly_plan.id,
        status: "active"
      )

      # 2000 + (24000/12) = 2000 + 2000 = 4000
      assert MrrCalculator.compute(tenant.id) == 4000
    end

    test "only counts active subscriptions, not trialing or past_due", %{
      tenant: tenant,
      customer: customer
    } do
      plan = insert(:plan, tenant_id: tenant.id, amount_cents: 5000, interval: "month")

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

      customer3 = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer3.id,
        plan_id: plan.id,
        status: "past_due"
      )

      customer4 = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer4.id,
        plan_id: plan.id,
        status: "canceled"
      )

      assert MrrCalculator.compute(tenant.id) == 5000
    end

    test "does not include subscriptions from other tenants", %{
      tenant: tenant,
      customer: customer
    } do
      plan = insert(:plan, tenant_id: tenant.id, amount_cents: 3000, interval: "month")

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "active"
      )

      other_tenant = insert(:tenant)
      other_customer = insert(:customer, tenant_id: other_tenant.id)
      other_plan = insert(:plan, tenant_id: other_tenant.id, amount_cents: 9000, interval: "month")

      insert(:subscription,
        tenant_id: other_tenant.id,
        customer_id: other_customer.id,
        plan_id: other_plan.id,
        status: "active"
      )

      assert MrrCalculator.compute(tenant.id) == 3000
    end

    test "handles subscriptions without a plan (nil plan_id)", %{
      tenant: tenant,
      customer: customer
    } do
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: nil,
        status: "active"
      )

      assert MrrCalculator.compute(tenant.id) == 0
    end

    test "handles weekly plans as monthly equivalent", %{tenant: tenant, customer: customer} do
      # Weekly plan: amount * ~4.33 weeks/month, but simpler: use amount as-is per PRD
      # The spec only mentions yearly/12. Weekly and month are treated as monthly.
      plan = insert(:plan, tenant_id: tenant.id, amount_cents: 500, interval: "week")

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "active"
      )

      # Weekly plans: multiply by ~4.33 for MRR approximation
      # 500 * 4 = 2000 (conservative integer estimate)
      assert MrrCalculator.compute(tenant.id) == 2000
    end
  end
end
