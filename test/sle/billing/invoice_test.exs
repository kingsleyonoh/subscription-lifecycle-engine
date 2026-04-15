defmodule SLE.Billing.InvoiceTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Billing.Invoice

  import SLE.Factory

  @valid_statuses ~w(draft open paid void uncollectible)

  describe "changeset/2 with valid data" do
    test "creates a valid changeset with all required fields" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_test_123",
        status: "open",
        amount_due_cents: 2999
      }

      changeset = Invoice.changeset(%Invoice{}, attrs)
      assert changeset.valid?
    end

    test "persists invoice to database" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_persist_1",
        stripe_charge_id: "ch_test_1",
        status: "paid",
        amount_due_cents: 4999,
        amount_paid_cents: 4999,
        currency: "eur",
        period_start: now,
        period_end: DateTime.add(now, 30, :day),
        due_date: DateTime.add(now, 7, :day),
        paid_at: now,
        hosted_invoice_url: "https://invoice.stripe.com/test"
      }

      changeset = Invoice.changeset(%Invoice{}, attrs)
      assert {:ok, invoice} = Repo.insert(changeset)
      assert invoice.id != nil
      assert invoice.tenant_id == tenant.id
      assert invoice.subscription_id == sub.id
      assert invoice.customer_id == customer.id
      assert invoice.stripe_invoice_id == "in_persist_1"
      assert invoice.stripe_charge_id == "ch_test_1"
      assert invoice.status == "paid"
      assert invoice.amount_due_cents == 4999
      assert invoice.amount_paid_cents == 4999
      assert invoice.currency == "eur"
    end
  end

  describe "changeset/2 required field validation" do
    test "requires tenant_id" do
      attrs = %{stripe_invoice_id: "in_x", status: "open", amount_due_cents: 100}
      changeset = Invoice.changeset(%Invoice{}, attrs)
      assert %{tenant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires stripe_invoice_id" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, status: "open", amount_due_cents: 100}
      changeset = Invoice.changeset(%Invoice{}, attrs)
      assert %{stripe_invoice_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires status" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, stripe_invoice_id: "in_x", amount_due_cents: 100}
      changeset = Invoice.changeset(%Invoice{}, attrs)
      assert %{status: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires amount_due_cents" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, stripe_invoice_id: "in_x", status: "open"}
      changeset = Invoice.changeset(%Invoice{}, attrs)
      assert %{amount_due_cents: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 status validation" do
    test "accepts all valid statuses" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      for status <- @valid_statuses do
        attrs = %{
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_status_#{status}",
          status: status,
          amount_due_cents: 1000
        }

        changeset = Invoice.changeset(%Invoice{}, attrs)
        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "rejects invalid status" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_invoice_id: "in_bad_status",
        status: "refunded",
        amount_due_cents: 100
      }

      changeset = Invoice.changeset(%Invoice{}, attrs)
      assert %{status: [_msg]} = errors_on(changeset)
    end
  end

  describe "changeset/2 defaults" do
    test "amount_paid_cents defaults to 0" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_default_paid",
        status: "open",
        amount_due_cents: 2000
      }

      {:ok, invoice} = %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()
      assert invoice.amount_paid_cents == 0
    end

    test "currency defaults to usd" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_default_cur",
        status: "open",
        amount_due_cents: 1000
      }

      {:ok, invoice} = %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()
      assert invoice.currency == "usd"
    end

    test "attempt_count defaults to 0" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_default_attempts",
        status: "open",
        amount_due_cents: 1000
      }

      {:ok, invoice} = %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()
      assert invoice.attempt_count == 0
    end

    test "synced_to_recon defaults to false" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_default_recon",
        status: "open",
        amount_due_cents: 1000
      }

      {:ok, invoice} = %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()
      assert invoice.synced_to_recon == false
    end

    test "metadata defaults to empty map" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_default_meta",
        status: "open",
        amount_due_cents: 1000
      }

      {:ok, invoice} = %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()
      assert invoice.metadata == %{}
    end
  end

  describe "changeset/2 uniqueness constraints" do
    test "enforces unique (tenant_id, stripe_invoice_id)" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_unique",
        status: "open",
        amount_due_cents: 1000
      }

      {:ok, _} = %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()

      attrs2 = %{attrs | amount_due_cents: 2000}
      assert {:error, changeset} = %Invoice{} |> Invoice.changeset(attrs2) |> Repo.insert()
      assert %{stripe_invoice_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same stripe_invoice_id for different tenants" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      customer_a = insert(:customer, tenant_id: tenant_a.id)
      customer_b = insert(:customer, tenant_id: tenant_b.id)
      sub_a = insert(:subscription, tenant_id: tenant_a.id, customer_id: customer_a.id)
      sub_b = insert(:subscription, tenant_id: tenant_b.id, customer_id: customer_b.id)

      base = %{stripe_invoice_id: "in_shared", status: "open", amount_due_cents: 1000}

      {:ok, _} =
        %Invoice{}
        |> Invoice.changeset(
          Map.merge(base, %{
            tenant_id: tenant_a.id,
            subscription_id: sub_a.id,
            customer_id: customer_a.id
          })
        )
        |> Repo.insert()

      assert {:ok, _} =
               %Invoice{}
               |> Invoice.changeset(
                 Map.merge(base, %{
                   tenant_id: tenant_b.id,
                   subscription_id: sub_b.id,
                   customer_id: customer_b.id
                 })
               )
               |> Repo.insert()
    end
  end

  describe "FK cascade behavior" do
    test "deleting tenant cascades to invoices" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      _invoice =
        insert(:invoice, tenant_id: tenant.id, subscription_id: sub.id, customer_id: customer.id)

      Repo.delete!(tenant)
      remaining = Repo.all(from i in Invoice, where: i.tenant_id == ^tenant.id)
      assert remaining == []
    end
  end

  describe "timestamps" do
    test "sets inserted_at and updated_at on insert" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_ts",
        status: "open",
        amount_due_cents: 500
      }

      {:ok, invoice} = %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()
      assert invoice.inserted_at != nil
      assert invoice.updated_at != nil
    end
  end
end
