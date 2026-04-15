defmodule SLE.BillingTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Billing

  import SLE.Factory

  describe "create_plan/2" do
    test "creates a new plan with valid attributes" do
      tenant = insert(:tenant)

      attrs = %{
        stripe_price_id: "price_create_1",
        name: "Starter Monthly",
        amount_cents: 1499,
        currency: "usd",
        interval: "month"
      }

      assert {:ok, plan} = Billing.create_plan(tenant.id, attrs)
      assert plan.tenant_id == tenant.id
      assert plan.stripe_price_id == "price_create_1"
      assert plan.name == "Starter Monthly"
      assert plan.amount_cents == 1499
    end

    test "returns error for missing required fields" do
      tenant = insert(:tenant)
      assert {:error, changeset} = Billing.create_plan(tenant.id, %{})
      assert %{stripe_price_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error for invalid interval" do
      tenant = insert(:tenant)

      attrs = %{
        stripe_price_id: "price_bad_int",
        name: "Bad",
        amount_cents: 100,
        interval: "quarterly"
      }

      assert {:error, changeset} = Billing.create_plan(tenant.id, attrs)
      assert %{interval: [_]} = errors_on(changeset)
    end
  end

  describe "upsert_plan/2" do
    test "inserts a new plan when stripe_price_id does not exist" do
      tenant = insert(:tenant)

      attrs = %{
        stripe_price_id: "price_upsert_new",
        name: "Upserted Plan",
        amount_cents: 2000,
        interval: "month"
      }

      assert {:ok, plan} = Billing.upsert_plan(tenant.id, attrs)
      assert plan.stripe_price_id == "price_upsert_new"
      assert plan.name == "Upserted Plan"
      assert plan.tenant_id == tenant.id
    end

    test "updates existing plan when stripe_price_id matches" do
      tenant = insert(:tenant)

      attrs = %{
        stripe_price_id: "price_upsert_existing",
        name: "Original Name",
        amount_cents: 1000,
        interval: "year"
      }

      {:ok, original} = Billing.upsert_plan(tenant.id, attrs)

      updated_attrs = %{
        stripe_price_id: "price_upsert_existing",
        name: "Updated Name",
        amount_cents: 1500,
        interval: "year"
      }

      {:ok, updated} = Billing.upsert_plan(tenant.id, updated_attrs)
      assert updated.id == original.id
      assert updated.name == "Updated Name"
      assert updated.amount_cents == 1500
    end

    test "upsert does not affect different tenant's plan" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      attrs = %{
        stripe_price_id: "price_shared_upsert",
        name: "Tenant A Plan",
        amount_cents: 1000,
        interval: "month"
      }

      {:ok, plan_a} = Billing.upsert_plan(tenant_a.id, attrs)

      attrs_b = %{attrs | name: "Tenant B Plan", amount_cents: 2000}
      {:ok, plan_b} = Billing.upsert_plan(tenant_b.id, attrs_b)

      assert plan_a.id != plan_b.id
      assert plan_a.name == "Tenant A Plan"
      assert plan_b.name == "Tenant B Plan"
    end
  end

  describe "list_plans/2" do
    test "returns only active plans scoped by tenant" do
      tenant = insert(:tenant)
      other_tenant = insert(:tenant)

      insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_list_1", is_active: true)
      insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_list_2", is_active: true)

      insert(:plan,
        tenant_id: tenant.id,
        stripe_price_id: "price_list_inactive",
        is_active: false
      )

      insert(:plan, tenant_id: other_tenant.id, stripe_price_id: "price_list_other")

      plans = Billing.list_plans(tenant.id)
      assert length(plans) == 2
      assert Enum.all?(plans, fn p -> p.tenant_id == tenant.id and p.is_active end)
    end

    test "returns all plans when include_inactive is true" do
      tenant = insert(:tenant)

      insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_all_1", is_active: true)
      insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_all_2", is_active: false)

      plans = Billing.list_plans(tenant.id, include_inactive: true)
      assert length(plans) == 2
    end

    test "returns empty list when tenant has no plans" do
      tenant = insert(:tenant)
      assert Billing.list_plans(tenant.id) == []
    end

    test "supports limit option" do
      tenant = insert(:tenant)

      for i <- 1..5 do
        insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_lim_#{i}")
      end

      plans = Billing.list_plans(tenant.id, limit: 3)
      assert length(plans) == 3
    end
  end

  describe "get_plan/2" do
    test "returns plan by id scoped to tenant" do
      tenant = insert(:tenant)
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_get_1")

      assert {:ok, found} = Billing.get_plan(tenant.id, plan.id)
      assert found.id == plan.id
      assert found.stripe_price_id == "price_get_1"
    end

    test "returns error for nonexistent plan" do
      tenant = insert(:tenant)
      assert {:error, :not_found} = Billing.get_plan(tenant.id, Ecto.UUID.generate())
    end

    test "tenant isolation: cannot see other tenant's plan" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      plan = insert(:plan, tenant_id: tenant_a.id, stripe_price_id: "price_isolated")

      assert {:error, :not_found} = Billing.get_plan(tenant_b.id, plan.id)
    end
  end

  describe "update_plan/3" do
    test "updates plan name" do
      tenant = insert(:tenant)

      plan =
        insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_update_1", name: "Old Name")

      assert {:ok, updated} = Billing.update_plan(tenant.id, plan.id, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "updates is_active" do
      tenant = insert(:tenant)

      plan =
        insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_deactivate", is_active: true)

      assert {:ok, updated} = Billing.update_plan(tenant.id, plan.id, %{is_active: false})
      assert updated.is_active == false
    end

    test "returns error for nonexistent plan" do
      tenant = insert(:tenant)

      assert {:error, :not_found} =
               Billing.update_plan(tenant.id, Ecto.UUID.generate(), %{name: "X"})
    end

    test "tenant isolation: cannot update other tenant's plan" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      plan = insert(:plan, tenant_id: tenant_a.id, stripe_price_id: "price_update_iso")

      assert {:error, :not_found} = Billing.update_plan(tenant_b.id, plan.id, %{name: "Hacked"})
    end
  end
end
