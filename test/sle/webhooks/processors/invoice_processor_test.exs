defmodule SLE.Webhooks.Processors.InvoiceProcessorTest do
  @moduledoc false

  use SLE.DataCase, async: true

  alias SLE.Billing.Invoice
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

  describe "process/1 — invoice.created" do
    test "creates invoice record from event" do
      tenant = insert(:tenant)

      payload =
        StripeEvents.invoice_event("invoice.created",
          stripe_invoice_id: "in_created_1",
          stripe_customer_id: "cus_inv_1",
          status: "draft",
          amount_due: 2999
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      invoice = Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_created_1")
      assert invoice != nil
      assert invoice.status == "draft"
      assert invoice.amount_due_cents == 2999
    end
  end

  describe "process/1 — invoice.updated" do
    test "updates existing invoice record" do
      tenant = insert(:tenant)

      _inv =
        insert(:invoice, tenant_id: tenant.id, stripe_invoice_id: "in_upd_1", status: "draft")

      payload =
        StripeEvents.invoice_event("invoice.updated",
          stripe_invoice_id: "in_upd_1",
          status: "open",
          amount_due: 3999
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      invoice = Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_upd_1")
      assert invoice.status == "open"
      assert invoice.amount_due_cents == 3999
    end
  end

  describe "process/1 — invoice.paid" do
    test "updates invoice status to paid and sets paid_at and amount_paid" do
      tenant = insert(:tenant)

      _inv =
        insert(:invoice, tenant_id: tenant.id, stripe_invoice_id: "in_paid_1", status: "open")

      paid_ts = System.system_time(:second)

      payload =
        StripeEvents.invoice_event("invoice.paid",
          stripe_invoice_id: "in_paid_1",
          status: "paid",
          amount_due: 2999,
          amount_paid: 2999,
          paid_at: paid_ts
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      invoice = Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_paid_1")
      assert invoice.status == "paid"
      assert invoice.amount_paid_cents == 2999
      assert invoice.paid_at != nil
    end
  end

  describe "process/1 — invoice.payment_failed" do
    test "updates invoice with attempt count" do
      tenant = insert(:tenant)

      _inv =
        insert(:invoice,
          tenant_id: tenant.id,
          stripe_invoice_id: "in_fail_1",
          status: "open",
          attempt_count: 0
        )

      payload =
        StripeEvents.invoice_event("invoice.payment_failed",
          stripe_invoice_id: "in_fail_1",
          status: "open",
          attempt_count: 1,
          amount_due: 2999,
          next_payment_attempt: System.system_time(:second) + 86_400
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      invoice = Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_fail_1")
      assert invoice.attempt_count == 1
      assert invoice.next_payment_attempt != nil
    end
  end

  describe "process/1 — invoice.voided" do
    test "updates invoice status to void" do
      tenant = insert(:tenant)

      _inv =
        insert(:invoice, tenant_id: tenant.id, stripe_invoice_id: "in_void_1", status: "open")

      payload =
        StripeEvents.invoice_event("invoice.voided",
          stripe_invoice_id: "in_void_1",
          status: "void",
          amount_due: 2999
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      invoice = Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_void_1")
      assert invoice.status == "void"
    end
  end

  describe "process/1 — invoice.finalized" do
    test "updates invoice status from draft to open" do
      tenant = insert(:tenant)

      _inv =
        insert(:invoice, tenant_id: tenant.id, stripe_invoice_id: "in_fin_1", status: "draft")

      payload =
        StripeEvents.invoice_event("invoice.finalized",
          stripe_invoice_id: "in_fin_1",
          status: "open",
          amount_due: 2999,
          hosted_invoice_url: "https://invoice.stripe.com/xxx"
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      invoice = Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_fin_1")
      assert invoice.status == "open"
      assert invoice.hosted_invoice_url == "https://invoice.stripe.com/xxx"
    end
  end

  describe "process/1 — subscription linking" do
    test "links invoice to subscription when stripe_subscription_id is present" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_link_1")

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          stripe_subscription_id: "sub_link_1",
          status: "active"
        )

      payload =
        StripeEvents.invoice_event("invoice.created",
          stripe_invoice_id: "in_link_1",
          stripe_customer_id: "cus_link_1",
          stripe_subscription_id: "sub_link_1",
          status: "draft",
          amount_due: 2999
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      invoice = Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_link_1")
      assert invoice.subscription_id == sub.id
      assert invoice.customer_id == customer.id
    end
  end

  describe "process/1 — creates new invoice" do
    test "creates invoice if none exists for the stripe_invoice_id" do
      tenant = insert(:tenant)

      payload =
        StripeEvents.invoice_event("invoice.paid",
          stripe_invoice_id: "in_new_paid",
          status: "paid",
          amount_due: 5000,
          amount_paid: 5000,
          paid_at: System.system_time(:second)
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = InvoiceProcessor.process(event)

      invoice = Repo.get_by(Invoice, tenant_id: tenant.id, stripe_invoice_id: "in_new_paid")
      assert invoice != nil
      assert invoice.status == "paid"
    end
  end
end
