defmodule SLE.Webhooks.Processors.InvoiceProcessorDunningTest do
  @moduledoc false

  use SLE.DataCase, async: true

  alias SLE.Dunning.DunningAttempt
  alias SLE.Subscriptions.Subscription
  alias SLE.Webhooks.Processors.InvoiceProcessor
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

  describe "process/1 — dunning recovery on invoice.paid" do
    test "recovers active dunning and transitions subscription to active" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_rec_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_rec_1")

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_rec_1",
          status: "past_due"
        )

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_rec_1",
          status: "open",
          amount_due_cents: 2999
        )

      _dunning =
        insert(:dunning_attempt,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          invoice_id: invoice.id,
          customer_id: customer.id,
          status: "retrying",
          attempt_number: 2,
          notification_payload: %{"template" => "dunning.payment_failed.reminder"}
        )

      payload =
        StripeEvents.invoice_event("invoice.paid",
          stripe_invoice_id: "in_rec_1",
          stripe_customer_id: "cus_rec_1",
          stripe_subscription_id: "sub_rec_1",
          status: "paid",
          amount_due: 2999,
          amount_paid: 2999,
          paid_at: System.system_time(:second)
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      reloaded_dunning =
        DunningAttempt
        |> where([d], d.tenant_id == ^tenant.id and d.invoice_id == ^invoice.id)
        |> Repo.one()

      assert reloaded_dunning.status == "recovered"
      assert reloaded_dunning.recovery_amount == 2999

      reloaded_sub = Repo.get!(Subscription, sub.id)
      assert reloaded_sub.status == "active"
    end

    test "does not attempt recovery when subscription is not past_due" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_norec_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_norec_1")

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_norec_1",
          status: "active"
        )

      _invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_norec_1",
          status: "open",
          amount_due_cents: 2999
        )

      payload =
        StripeEvents.invoice_event("invoice.paid",
          stripe_invoice_id: "in_norec_1",
          stripe_customer_id: "cus_norec_1",
          stripe_subscription_id: "sub_norec_1",
          status: "paid",
          amount_due: 2999,
          amount_paid: 2999,
          paid_at: System.system_time(:second)
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      # Subscription should still be active
      reloaded_sub = Repo.get!(Subscription, sub.id)
      assert reloaded_sub.status == "active"
    end

    test "handles no dunning attempt for the invoice gracefully" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_nodun_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_nodun_1")

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_nodun_1",
          status: "past_due"
        )

      _invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_nodun_1",
          status: "open",
          amount_due_cents: 2999
        )

      payload =
        StripeEvents.invoice_event("invoice.paid",
          stripe_invoice_id: "in_nodun_1",
          stripe_customer_id: "cus_nodun_1",
          stripe_subscription_id: "sub_nodun_1",
          status: "paid",
          amount_due: 2999,
          amount_paid: 2999,
          paid_at: System.system_time(:second)
        )

      event = build_event(tenant, payload)
      # Should not crash even when no dunning exists
      assert {:ok, _result} = InvoiceProcessor.process(event)
    end

    test "does not recover already-recovered dunning" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_rr_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_rr_1")

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_rr_1",
          status: "past_due"
        )

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_rr_1",
          status: "open",
          amount_due_cents: 2999
        )

      _dunning =
        insert(:dunning_attempt,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          invoice_id: invoice.id,
          customer_id: customer.id,
          status: "recovered",
          recovery_amount: 2999,
          notification_payload: %{"template" => "dunning.recovered"}
        )

      payload =
        StripeEvents.invoice_event("invoice.paid",
          stripe_invoice_id: "in_rr_1",
          stripe_customer_id: "cus_rr_1",
          stripe_subscription_id: "sub_rr_1",
          status: "paid",
          amount_due: 2999,
          amount_paid: 2999,
          paid_at: System.system_time(:second)
        )

      event = build_event(tenant, payload)
      # Should not crash when dunning is already recovered
      assert {:ok, _result} = InvoiceProcessor.process(event)
    end
  end
end
