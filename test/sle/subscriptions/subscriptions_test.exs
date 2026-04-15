defmodule SLE.SubscriptionsTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Subscriptions
  alias SLE.Subscriptions.Subscription

  import SLE.Factory

  # --- transition/3 ---

  describe "transition/3" do
    test "transitions subscription from trialing to active" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "trialing")

      assert {:ok, updated} = Subscriptions.transition(tenant.id, sub.id, "active")
      assert updated.status == "active"
    end

    test "transitions subscription from active to past_due" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      assert {:ok, updated} = Subscriptions.transition(tenant.id, sub.id, "past_due")
      assert updated.status == "past_due"
    end

    test "rejects invalid transition from canceled to active" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "canceled")

      assert {:error, :invalid_transition} = Subscriptions.transition(tenant.id, sub.id, "active")
    end

    test "returns not_found for nonexistent subscription" do
      tenant = insert(:tenant)

      assert {:error, :not_found} =
               Subscriptions.transition(tenant.id, Ecto.UUID.generate(), "active")
    end

    test "tenant isolation: cannot transition other tenant's subscription" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant_a.id)

      sub =
        insert(:subscription, tenant_id: tenant_a.id, customer_id: customer.id, status: "active")

      assert {:error, :not_found} = Subscriptions.transition(tenant_b.id, sub.id, "past_due")
    end
  end

  # --- list/2 ---

  describe "list/2" do
    test "returns subscriptions scoped by tenant" do
      tenant = insert(:tenant)
      other_tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      other_customer = insert(:customer, tenant_id: other_tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_l1"
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_l2"
      )

      insert(:subscription,
        tenant_id: other_tenant.id,
        customer_id: other_customer.id,
        stripe_subscription_id: "sub_l3"
      )

      subs = Subscriptions.list(tenant.id)
      assert length(subs) == 2
      assert Enum.all?(subs, fn s -> s.tenant_id == tenant.id end)
    end

    test "filters by status" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        status: "active",
        stripe_subscription_id: "sub_f1"
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        status: "canceled",
        stripe_subscription_id: "sub_f2"
      )

      subs = Subscriptions.list(tenant.id, status: "active")
      assert length(subs) == 1
      assert hd(subs).status == "active"
    end

    test "filters by customer_id" do
      tenant = insert(:tenant)
      customer_a = insert(:customer, tenant_id: tenant.id)
      customer_b = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer_a.id,
        stripe_subscription_id: "sub_ca"
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer_b.id,
        stripe_subscription_id: "sub_cb"
      )

      subs = Subscriptions.list(tenant.id, customer_id: customer_a.id)
      assert length(subs) == 1
      assert hd(subs).customer_id == customer_a.id
    end

    test "filters by plan_id" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      plan_a = insert(:plan, tenant_id: tenant.id)
      plan_b = insert(:plan, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan_a.id,
        stripe_subscription_id: "sub_pa"
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan_b.id,
        stripe_subscription_id: "sub_pb"
      )

      subs = Subscriptions.list(tenant.id, plan_id: plan_a.id)
      assert length(subs) == 1
      assert hd(subs).plan_id == plan_a.id
    end

    test "supports limit option" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      for i <- 1..5 do
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          stripe_subscription_id: "sub_lim_#{i}"
        )
      end

      subs = Subscriptions.list(tenant.id, limit: 3)
      assert length(subs) == 3
    end

    test "returns empty list when tenant has no subscriptions" do
      tenant = insert(:tenant)
      assert Subscriptions.list(tenant.id) == []
    end
  end

  # --- get/2 ---

  describe "get/2" do
    test "returns subscription by id scoped to tenant with preloads" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, plan_id: plan.id)

      assert {:ok, found} = Subscriptions.get(tenant.id, sub.id)
      assert found.id == sub.id
      assert found.customer.id == customer.id
      assert found.plan.id == plan.id
    end

    test "returns error for nonexistent subscription" do
      tenant = insert(:tenant)
      assert {:error, :not_found} = Subscriptions.get(tenant.id, Ecto.UUID.generate())
    end

    test "tenant isolation: cannot see other tenant's subscription" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant_a.id)
      sub = insert(:subscription, tenant_id: tenant_a.id, customer_id: customer.id)

      assert {:error, :not_found} = Subscriptions.get(tenant_b.id, sub.id)
    end
  end

  # --- cancel/3 ---

  describe "cancel/3" do
    test "cancels active subscription immediately" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      assert {:ok, updated} = Subscriptions.cancel(tenant.id, sub.id, immediate: true)
      assert updated.status == "canceled"
      assert updated.canceled_at != nil
    end

    test "sets cancel_at_period_end for active subscription" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      assert {:ok, updated} = Subscriptions.cancel(tenant.id, sub.id, at_period_end: true)
      assert updated.cancel_at_period_end == true
      # Status stays active when cancel_at_period_end
      assert updated.status == "active"
    end

    test "cancels trialing subscription" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "trialing")

      assert {:ok, updated} = Subscriptions.cancel(tenant.id, sub.id, immediate: true)
      assert updated.status == "canceled"
    end

    test "rejects canceling a paused subscription" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "paused")

      assert {:error, :invalid_transition} =
               Subscriptions.cancel(tenant.id, sub.id, immediate: true)
    end
  end

  # --- pause/2 ---

  describe "pause/2" do
    test "pauses active subscription" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      assert {:ok, updated} = Subscriptions.pause(tenant.id, sub.id)
      assert updated.status == "paused"
    end

    test "rejects pausing from past_due (409 conflict)" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "past_due")

      assert {:error, :conflict} = Subscriptions.pause(tenant.id, sub.id)
    end

    test "rejects pausing from trialing" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "trialing")

      assert {:error, :invalid_transition} = Subscriptions.pause(tenant.id, sub.id)
    end
  end

  # --- resume/2 ---

  describe "resume/2" do
    test "resumes paused subscription" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "paused")

      assert {:ok, updated} = Subscriptions.resume(tenant.id, sub.id)
      assert updated.status == "active"
    end

    test "rejects resuming from active" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      assert {:error, :not_paused} = Subscriptions.resume(tenant.id, sub.id)
    end
  end

  # --- upsert_from_stripe/2 ---

  describe "upsert_from_stripe/2" do
    test "creates a new subscription from stripe data" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id)

      stripe_data = %{
        "id" => "sub_stripe_new",
        "status" => "trialing",
        "customer" => customer.stripe_customer_id,
        "items" => %{
          "data" => [%{"price" => %{"id" => plan.stripe_price_id}}]
        },
        "current_period_start" => 1_700_000_000,
        "current_period_end" => 1_702_592_000,
        "trial_start" => 1_700_000_000,
        "trial_end" => 1_701_209_600
      }

      assert {:ok, sub} = Subscriptions.upsert_from_stripe(tenant.id, stripe_data)
      assert sub.stripe_subscription_id == "sub_stripe_new"
      assert sub.status == "trialing"
      assert sub.customer_id == customer.id
      assert sub.plan_id == plan.id
    end

    test "updates existing subscription from stripe data" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          status: "trialing",
          stripe_subscription_id: "sub_stripe_upsert"
        )

      stripe_data = %{
        "id" => "sub_stripe_upsert",
        "status" => "active",
        "customer" => customer.stripe_customer_id,
        "items" => %{"data" => []},
        "current_period_start" => 1_700_000_000,
        "current_period_end" => 1_702_592_000
      }

      assert {:ok, updated} = Subscriptions.upsert_from_stripe(tenant.id, stripe_data)
      assert updated.id == sub.id
      assert updated.status == "active"
    end

    test "does not create subscription for nonexistent customer" do
      tenant = insert(:tenant)

      stripe_data = %{
        "id" => "sub_orphan",
        "status" => "active",
        "customer" => "cus_nonexistent",
        "items" => %{"data" => []}
      }

      assert {:error, :customer_not_found} =
               Subscriptions.upsert_from_stripe(tenant.id, stripe_data)
    end
  end
end
