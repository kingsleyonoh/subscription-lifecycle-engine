defmodule SLE.Webhooks.Processors.SubscriptionProcessorTest do
  @moduledoc false

  use SLE.DataCase, async: true

  alias SLE.Customers.Customer
  alias SLE.Billing.Plan
  alias SLE.Subscriptions.{Subscription, SubscriptionEvent}
  alias SLE.Webhooks.Processors.SubscriptionProcessor
  alias SLE.Fixtures.StripeEvents

  import SLE.Factory

  defp build_event(tenant, event_payload) do
    insert(:subscription_event,
      tenant_id: tenant.id,
      event_type: event_payload["type"],
      payload: event_payload,
      processed_at: nil
    )
  end

  describe "process/1 — customer.subscription.created" do
    test "creates customer, plan, and subscription from event" do
      tenant = insert(:tenant)

      payload =
        StripeEvents.subscription_created(
          stripe_sub_id: "sub_new_1",
          stripe_customer_id: "cus_new_1",
          stripe_price_id: "price_new_1",
          status: "trialing",
          amount_cents: 1999,
          trial_start: 1_714_000_000,
          trial_end: 1_715_209_600
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      # Customer was created
      customer = Repo.get_by(Customer, tenant_id: tenant.id, stripe_customer_id: "cus_new_1")
      assert customer != nil

      # Plan was created
      plan = Repo.get_by(Plan, tenant_id: tenant.id, stripe_price_id: "price_new_1")
      assert plan != nil
      assert plan.amount_cents == 1999

      # Subscription was created
      sub = Repo.get_by(Subscription, tenant_id: tenant.id, stripe_subscription_id: "sub_new_1")
      assert sub != nil
      assert sub.status == "trialing"
      assert sub.customer_id == customer.id
      assert sub.plan_id == plan.id
      assert sub.trial_start != nil
      assert sub.trial_end != nil

      # Event was updated with status info
      updated_event = Repo.get!(SubscriptionEvent, event.id)
      assert updated_event.new_status == "trialing"
      assert updated_event.subscription_id == sub.id
    end

    test "upserts existing customer when customer already exists" do
      tenant = insert(:tenant)
      _existing = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_existing")

      payload =
        StripeEvents.subscription_created(
          stripe_sub_id: "sub_upsert_1",
          stripe_customer_id: "cus_existing",
          stripe_price_id: "price_upsert_1",
          status: "active"
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      # Should still have exactly one customer
      customers =
        Customer
        |> where([c], c.tenant_id == ^tenant.id and c.stripe_customer_id == "cus_existing")
        |> Repo.all()

      assert length(customers) == 1
    end

    test "upserts existing plan when plan already exists" do
      tenant = insert(:tenant)
      existing_plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_existing")

      payload =
        StripeEvents.subscription_created(
          stripe_sub_id: "sub_plan_upsert",
          stripe_customer_id: "cus_plan_upsert",
          stripe_price_id: "price_existing",
          status: "active"
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      # Plan should still be the same record
      plans =
        Plan
        |> where([p], p.tenant_id == ^tenant.id and p.stripe_price_id == "price_existing")
        |> Repo.all()

      assert length(plans) == 1
      assert hd(plans).id == existing_plan.id
    end

    test "logs warning for multiple items and takes first price" do
      tenant = insert(:tenant)

      extra_items = [
        %{
          "price" => %{
            "id" => "price_second",
            "unit_amount" => 500,
            "currency" => "usd",
            "recurring" => %{"interval" => "month"},
            "product" => "prod_addon"
          }
        }
      ]

      payload =
        StripeEvents.subscription_created(
          stripe_sub_id: "sub_multi_item",
          stripe_customer_id: "cus_multi_item",
          stripe_price_id: "price_first",
          status: "active",
          extra_items: extra_items
        )

      event = build_event(tenant, payload)

      assert {:ok, _result} = SubscriptionProcessor.process(event)

      # Should use the first item's price
      plan = Repo.get_by(Plan, tenant_id: tenant.id, stripe_price_id: "price_first")
      assert plan != nil
    end
  end

  describe "process/1 — customer.subscription.updated" do
    test "updates subscription status via valid state transition" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_update_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_update_1")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_update_1",
          status: "trialing"
        )

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_update_1",
          stripe_customer_id: "cus_update_1",
          stripe_price_id: "price_update_1",
          status: "active",
          previous_attributes: %{"status" => "trialing"}
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      updated_sub =
        Repo.get_by(Subscription, tenant_id: tenant.id, stripe_subscription_id: "sub_update_1")

      assert updated_sub.status == "active"

      updated_event = Repo.get!(SubscriptionEvent, event.id)
      assert updated_event.previous_status == "trialing"
      assert updated_event.new_status == "active"
    end

    test "skips status update on invalid transition but updates other fields" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_invalid_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_invalid_1")

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      new_period_end = DateTime.add(now, 60 * 86_400, :second) |> DateTime.truncate(:second)

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_invalid_1",
          status: "canceled"
        )

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_invalid_1",
          stripe_customer_id: "cus_invalid_1",
          stripe_price_id: "price_invalid_1",
          status: "active",
          period_end: DateTime.to_unix(new_period_end)
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      updated_sub =
        Repo.get_by(Subscription, tenant_id: tenant.id, stripe_subscription_id: "sub_invalid_1")

      # Status should NOT change (canceled is terminal)
      assert updated_sub.status == "canceled"
      # But period_end should be updated
      assert updated_sub.current_period_end == new_period_end
    end

    test "cancel_at_period_end=true records canceled_at but does not change status" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_cap_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_cap_1")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_cap_1",
          status: "active"
        )

      canceled_ts = System.system_time(:second)

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_cap_1",
          stripe_customer_id: "cus_cap_1",
          stripe_price_id: "price_cap_1",
          status: "active",
          cancel_at_period_end: true,
          canceled_at: canceled_ts
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      updated_sub =
        Repo.get_by(Subscription, tenant_id: tenant.id, stripe_subscription_id: "sub_cap_1")

      assert updated_sub.status == "active"
      assert updated_sub.cancel_at_period_end == true
      assert updated_sub.canceled_at != nil
    end

    test "updates period dates on subscription renewal" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_renew_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_renew_1")

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_renew_1",
          status: "active",
          current_period_start: DateTime.add(now, -30, :day),
          current_period_end: now
        )

      new_start = DateTime.to_unix(now)
      new_end = DateTime.to_unix(DateTime.add(now, 30, :day))

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_renew_1",
          stripe_customer_id: "cus_renew_1",
          stripe_price_id: "price_renew_1",
          status: "active",
          period_start: new_start,
          period_end: new_end
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      updated_sub =
        Repo.get_by(Subscription, tenant_id: tenant.id, stripe_subscription_id: "sub_renew_1")

      assert DateTime.to_unix(updated_sub.current_period_start) == new_start
      assert DateTime.to_unix(updated_sub.current_period_end) == new_end
    end
  end

  describe "process/1 — customer.subscription.deleted" do
    test "transitions subscription to canceled on deleted event" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_del_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_del_1")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_del_1",
          status: "active"
        )

      ended_ts = System.system_time(:second)

      payload =
        StripeEvents.subscription_deleted(
          stripe_sub_id: "sub_del_1",
          stripe_customer_id: "cus_del_1",
          stripe_price_id: "price_del_1",
          ended_at: ended_ts
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      updated_sub =
        Repo.get_by(Subscription, tenant_id: tenant.id, stripe_subscription_id: "sub_del_1")

      assert updated_sub.status == "canceled"
      assert updated_sub.ended_at != nil

      updated_event = Repo.get!(SubscriptionEvent, event.id)
      assert updated_event.previous_status == "active"
      assert updated_event.new_status == "canceled"
    end

    test "creates subscription record if none exists on deleted event" do
      tenant = insert(:tenant)

      payload =
        StripeEvents.subscription_deleted(
          stripe_sub_id: "sub_del_new",
          stripe_customer_id: "cus_del_new",
          stripe_price_id: "price_del_new"
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      sub =
        Repo.get_by(Subscription,
          tenant_id: tenant.id,
          stripe_subscription_id: "sub_del_new"
        )

      assert sub != nil
      assert sub.status == "canceled"
    end
  end
end
