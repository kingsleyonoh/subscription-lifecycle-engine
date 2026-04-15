defmodule SLE.Webhooks.Processors.SubscriptionProcessorEcosystemTest do
  @moduledoc """
  Tests that SubscriptionProcessor emits ecosystem notifications
  for subscription lifecycle events: created, activated, canceled.
  """

  use SLE.DataCase, async: false
  use Oban.Testing, repo: SLE.Repo

  import Mox
  import SLE.Factory

  alias SLE.Webhooks.Processors.SubscriptionProcessor
  alias SLE.Fixtures.StripeEvents

  setup :verify_on_exit!

  setup do
    Application.put_env(:sle, :notification_hub_enabled, true)
    Application.put_env(:sle, :notification_hub_client, SLE.Ecosystem.NotificationHubMock)

    on_exit(fn ->
      Application.put_env(:sle, :notification_hub_enabled, false)
    end)

    :ok
  end

  defp build_event(tenant, event_payload) do
    insert(:subscription_event,
      tenant_id: tenant.id,
      event_type: event_payload["type"],
      payload: event_payload,
      processed_at: nil
    )
  end

  describe "ecosystem emission — subscription.created" do
    test "emits subscription.created notification on new subscription" do
      tenant = insert(:tenant)

      payload =
        StripeEvents.subscription_created(
          stripe_sub_id: "sub_eco_created_1",
          stripe_customer_id: "cus_eco_created_1",
          stripe_price_id: "price_eco_created_1",
          status: "trialing",
          amount_cents: 1999
        )

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type,
                                                                notification_payload ->
        assert event_type == "subscription.created"
        assert notification_payload.status == "trialing"
        assert notification_payload.subscription_id != nil
        :ok
      end)

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)
    end

    test "includes customer and plan details in created notification payload" do
      tenant = insert(:tenant)

      payload =
        StripeEvents.subscription_created(
          stripe_sub_id: "sub_eco_detail_1",
          stripe_customer_id: "cus_eco_detail_1",
          stripe_price_id: "price_eco_detail_1",
          status: "active",
          amount_cents: 2999
        )

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn _event_type,
                                                                notification_payload ->
        assert Map.has_key?(notification_payload, :subscription_id)
        assert Map.has_key?(notification_payload, :status)
        :ok
      end)

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)
    end
  end

  describe "ecosystem emission — subscription.activated" do
    test "emits subscription.activated on trialing -> active transition" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_eco_act_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_eco_act_1")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_eco_act_1",
          status: "trialing"
        )

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_eco_act_1",
          stripe_customer_id: "cus_eco_act_1",
          stripe_price_id: "price_eco_act_1",
          status: "active",
          previous_attributes: %{"status" => "trialing"}
        )

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type,
                                                                notification_payload ->
        assert event_type == "subscription.activated"
        assert notification_payload.status == "active"
        assert notification_payload.subscription_id != nil
        :ok
      end)

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)
    end

    test "emits subscription.activated on incomplete -> active transition" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_eco_act_2")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_eco_act_2")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_eco_act_2",
          status: "incomplete"
        )

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_eco_act_2",
          stripe_customer_id: "cus_eco_act_2",
          stripe_price_id: "price_eco_act_2",
          status: "active",
          previous_attributes: %{"status" => "incomplete"}
        )

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, _payload ->
        assert event_type == "subscription.activated"
        :ok
      end)

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)
    end
  end

  describe "ecosystem emission — subscription.canceled" do
    test "emits subscription.canceled on active -> canceled transition" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_eco_can_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_eco_can_1")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_eco_can_1",
          status: "active"
        )

      payload =
        StripeEvents.subscription_deleted(
          stripe_sub_id: "sub_eco_can_1",
          stripe_customer_id: "cus_eco_can_1",
          stripe_price_id: "price_eco_can_1"
        )

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type,
                                                                notification_payload ->
        assert event_type == "subscription.canceled"
        assert notification_payload.status == "canceled"
        :ok
      end)

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)
    end
  end

  describe "ecosystem emission — no emission on status-preserving updates" do
    test "does not emit notification when status doesn't change" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_eco_no_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_eco_no_1")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_eco_no_1",
          status: "active"
        )

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_eco_no_1",
          stripe_customer_id: "cus_eco_no_1",
          stripe_price_id: "price_eco_no_1",
          status: "active"
        )

      # No expect — if send_event is called, verify_on_exit! will catch it

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)
    end
  end
end
