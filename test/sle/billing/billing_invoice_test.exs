defmodule SLE.Billing.InvoiceContextTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Billing
  alias SLE.Billing.Invoice

  import SLE.Factory

  # --- upsert_invoice/2 ---

  describe "upsert_invoice/2" do
    test "creates a new invoice from stripe data" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      stripe_data = %{
        "id" => "in_stripe_new",
        "subscription" => sub.stripe_subscription_id,
        "customer" => customer.stripe_customer_id,
        "charge" => "ch_test_abc",
        "status" => "open",
        "amount_due" => 2999,
        "amount_paid" => 0,
        "currency" => "usd",
        "period_start" => 1_700_000_000,
        "period_end" => 1_702_592_000,
        "due_date" => 1_700_604_800,
        "attempt_count" => 1,
        "next_payment_attempt" => 1_700_259_200,
        "hosted_invoice_url" => "https://invoice.stripe.com/test"
      }

      assert {:ok, invoice} = Billing.upsert_invoice(tenant.id, stripe_data)
      assert invoice.stripe_invoice_id == "in_stripe_new"
      assert invoice.status == "open"
      assert invoice.amount_due_cents == 2999
      assert invoice.subscription_id == sub.id
      assert invoice.customer_id == customer.id
    end

    test "updates existing invoice from stripe data" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_stripe_upsert",
          status: "open",
          amount_due_cents: 2000
        )

      stripe_data = %{
        "id" => "in_stripe_upsert",
        "subscription" => sub.stripe_subscription_id,
        "customer" => customer.stripe_customer_id,
        "status" => "paid",
        "amount_due" => 2000,
        "amount_paid" => 2000,
        "currency" => "usd"
      }

      assert {:ok, updated} = Billing.upsert_invoice(tenant.id, stripe_data)
      assert updated.id == invoice.id
      assert updated.status == "paid"
      assert updated.amount_paid_cents == 2000
    end

    test "tenant isolation: upsert does not affect other tenant's invoice" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      customer_a = insert(:customer, tenant_id: tenant_a.id)
      customer_b = insert(:customer, tenant_id: tenant_b.id)
      sub_a = insert(:subscription, tenant_id: tenant_a.id, customer_id: customer_a.id)
      sub_b = insert(:subscription, tenant_id: tenant_b.id, customer_id: customer_b.id)

      insert(:invoice,
        tenant_id: tenant_a.id,
        subscription_id: sub_a.id,
        customer_id: customer_a.id,
        stripe_invoice_id: "in_shared_upsert"
      )

      stripe_data = %{
        "id" => "in_shared_upsert",
        "subscription" => sub_b.stripe_subscription_id,
        "customer" => customer_b.stripe_customer_id,
        "status" => "open",
        "amount_due" => 3000,
        "amount_paid" => 0,
        "currency" => "usd"
      }

      # Tenant B creates a NEW invoice (same stripe id, different tenant)
      assert {:ok, new_invoice} = Billing.upsert_invoice(tenant_b.id, stripe_data)
      assert new_invoice.tenant_id == tenant_b.id

      # Verify tenant A's invoice is untouched
      [inv_a] = Repo.all(from i in Invoice, where: i.tenant_id == ^tenant_a.id)
      assert inv_a.tenant_id == tenant_a.id
    end
  end

  # --- list_invoices/2 ---

  describe "list_invoices/2" do
    test "returns invoices scoped by tenant" do
      tenant = insert(:tenant)
      other_tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      other_customer = insert(:customer, tenant_id: other_tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      other_sub =
        insert(:subscription, tenant_id: other_tenant.id, customer_id: other_customer.id)

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_l1"
      )

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_l2"
      )

      insert(:invoice,
        tenant_id: other_tenant.id,
        subscription_id: other_sub.id,
        customer_id: other_customer.id,
        stripe_invoice_id: "in_l3"
      )

      invoices = Billing.list_invoices(tenant.id)
      assert length(invoices) == 2
      assert Enum.all?(invoices, fn i -> i.tenant_id == tenant.id end)
    end

    test "filters by status" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        status: "open",
        stripe_invoice_id: "in_fs1"
      )

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        status: "paid",
        stripe_invoice_id: "in_fs2"
      )

      invoices = Billing.list_invoices(tenant.id, status: "paid")
      assert length(invoices) == 1
      assert hd(invoices).status == "paid"
    end

    test "filters by subscription_id" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      sub_a =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          stripe_subscription_id: "sub_inv_a"
        )

      sub_b =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          stripe_subscription_id: "sub_inv_b"
        )

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub_a.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_fsa"
      )

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub_b.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_fsb"
      )

      invoices = Billing.list_invoices(tenant.id, subscription_id: sub_a.id)
      assert length(invoices) == 1
      assert hd(invoices).subscription_id == sub_a.id
    end

    test "supports limit option" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      for i <- 1..5 do
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_lim_#{i}"
        )
      end

      invoices = Billing.list_invoices(tenant.id, limit: 3)
      assert length(invoices) == 3
    end

    test "returns empty list when tenant has no invoices" do
      tenant = insert(:tenant)
      assert Billing.list_invoices(tenant.id) == []
    end
  end

  # --- get_invoice/2 ---

  describe "get_invoice/2" do
    test "returns invoice by id scoped to tenant" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_get_1"
        )

      assert {:ok, found} = Billing.get_invoice(tenant.id, invoice.id)
      assert found.id == invoice.id
      assert found.stripe_invoice_id == "in_get_1"
    end

    test "returns error for nonexistent invoice" do
      tenant = insert(:tenant)
      assert {:error, :not_found} = Billing.get_invoice(tenant.id, Ecto.UUID.generate())
    end

    test "tenant isolation: cannot see other tenant's invoice" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant_a.id)
      sub = insert(:subscription, tenant_id: tenant_a.id, customer_id: customer.id)

      invoice =
        insert(:invoice,
          tenant_id: tenant_a.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_iso"
        )

      assert {:error, :not_found} = Billing.get_invoice(tenant_b.id, invoice.id)
    end
  end
end
