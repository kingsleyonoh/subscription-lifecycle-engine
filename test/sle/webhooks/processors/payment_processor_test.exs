defmodule SLE.Webhooks.Processors.PaymentProcessorTest do
  @moduledoc false

  use SLE.DataCase, async: true

  alias SLE.Billing.Invoice
  alias SLE.Webhooks.Processors.PaymentProcessor
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

  describe "process/1 — payment_intent.succeeded" do
    test "updates invoice charge_id when invoice matches" do
      tenant = insert(:tenant)

      _inv =
        insert(:invoice,
          tenant_id: tenant.id,
          stripe_invoice_id: "in_pi_success_1",
          status: "open"
        )

      payload =
        StripeEvents.payment_intent_event("payment_intent.succeeded",
          stripe_invoice_id: "in_pi_success_1",
          charge_id: "ch_new_1",
          status: "succeeded"
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = PaymentProcessor.process(event)

      invoice =
        Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_pi_success_1")

      assert invoice.stripe_charge_id == "ch_new_1"
    end

    test "returns ok when no matching invoice exists" do
      tenant = insert(:tenant)

      payload =
        StripeEvents.payment_intent_event("payment_intent.succeeded",
          stripe_invoice_id: nil,
          charge_id: "ch_orphan",
          status: "succeeded"
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = PaymentProcessor.process(event)
    end
  end

  describe "process/1 — payment_intent.payment_failed" do
    test "updates invoice attempt info on failure" do
      tenant = insert(:tenant)

      _inv =
        insert(:invoice,
          tenant_id: tenant.id,
          stripe_invoice_id: "in_pi_fail_1",
          status: "open"
        )

      payload =
        StripeEvents.payment_intent_event("payment_intent.payment_failed",
          stripe_invoice_id: "in_pi_fail_1",
          charge_id: "ch_fail_1",
          status: "requires_payment_method"
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = PaymentProcessor.process(event)

      invoice =
        Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_pi_fail_1")

      assert invoice.stripe_charge_id == "ch_fail_1"
    end

    test "returns ok when invoice not found for failed payment" do
      tenant = insert(:tenant)

      payload =
        StripeEvents.payment_intent_event("payment_intent.payment_failed",
          stripe_invoice_id: "in_nonexistent",
          charge_id: "ch_fail_orphan",
          status: "requires_payment_method"
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = PaymentProcessor.process(event)
    end
  end
end
