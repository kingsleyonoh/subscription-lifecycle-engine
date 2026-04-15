defmodule SLE.Webhooks.EventRouterTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Webhooks.EventRouter

  import SLE.Factory

  describe "route/1" do
    test "routes customer.subscription.created to SubscriptionProcessor" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "customer.subscription.created"
        )

      assert {:ok, :subscription_processor} = EventRouter.route(event)
    end

    test "routes customer.subscription.updated to SubscriptionProcessor" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "customer.subscription.updated"
        )

      assert {:ok, :subscription_processor} = EventRouter.route(event)
    end

    test "routes customer.subscription.deleted to SubscriptionProcessor" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "customer.subscription.deleted"
        )

      assert {:ok, :subscription_processor} = EventRouter.route(event)
    end

    test "routes invoice.paid to InvoiceProcessor" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "invoice.paid"
        )

      assert {:ok, :invoice_processor} = EventRouter.route(event)
    end

    test "routes invoice.payment_failed to InvoiceProcessor" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "invoice.payment_failed"
        )

      assert {:ok, :invoice_processor} = EventRouter.route(event)
    end

    test "routes payment_intent.succeeded to PaymentProcessor" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "payment_intent.succeeded"
        )

      assert {:ok, :payment_processor} = EventRouter.route(event)
    end

    test "routes payment_intent.payment_failed to PaymentProcessor" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "payment_intent.payment_failed"
        )

      assert {:ok, :payment_processor} = EventRouter.route(event)
    end

    test "returns {:ok, :unknown} for unrecognized event types" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "checkout.session.completed"
        )

      assert {:ok, :unknown} = EventRouter.route(event)
    end
  end
end
