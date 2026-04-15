defmodule SLE.Jobs.ReconSyncJobTest do
  @moduledoc false

  use SLE.DataCase, async: false
  use Oban.Testing, repo: SLE.Repo

  import Mox
  import SLE.Factory

  alias SLE.Billing.Invoice
  alias SLE.Jobs.ReconSyncJob

  setup :verify_on_exit!

  describe "perform/1" do
    test "syncs unsynced paid invoices to recon engine" do
      Application.put_env(:sle, :recon_engine_enabled, true)
      Application.put_env(:sle, :recon_engine_client, SLE.Ecosystem.ReconEngineMock)

      on_exit(fn ->
        Application.put_env(:sle, :recon_engine_enabled, false)
      end)

      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, email: "user@example.com")
      plan = insert(:plan, tenant_id: tenant.id)

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id
        )

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_sync_001",
          stripe_charge_id: "ch_sync_001",
          status: "paid",
          amount_paid_cents: 4999,
          currency: "usd",
          paid_at: ~U[2026-04-14 10:30:00Z],
          synced_to_recon: false
        )

      expect(SLE.Ecosystem.ReconEngineMock, :sync_transactions, fn txns ->
        assert length(txns) == 1
        [txn] = txns
        assert txn.reference == "in_sync_001"
        assert txn.amount == 4999
        assert txn.currency == "usd"
        assert txn.type == "credit"
        assert txn.source == "stripe"
        assert txn.metadata.stripe_charge_id == "ch_sync_001"
        assert txn.metadata.customer_email == "user@example.com"
        {:ok, %{synced: 1}}
      end)

      assert :ok = ReconSyncJob.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(Invoice, invoice.id)
      assert updated.synced_to_recon == true
    end

    test "skips already-synced invoices" do
      Application.put_env(:sle, :recon_engine_enabled, true)
      Application.put_env(:sle, :recon_engine_client, SLE.Ecosystem.ReconEngineMock)

      on_exit(fn ->
        Application.put_env(:sle, :recon_engine_enabled, false)
      end)

      tenant = insert(:tenant)

      insert(:invoice,
        tenant_id: tenant.id,
        status: "paid",
        synced_to_recon: true
      )

      # No mock expectation — sync_transactions should not be called
      assert :ok = ReconSyncJob.perform(%Oban.Job{args: %{}})
    end

    test "skips non-paid invoices" do
      Application.put_env(:sle, :recon_engine_enabled, true)
      Application.put_env(:sle, :recon_engine_client, SLE.Ecosystem.ReconEngineMock)

      on_exit(fn ->
        Application.put_env(:sle, :recon_engine_enabled, false)
      end)

      tenant = insert(:tenant)

      insert(:invoice,
        tenant_id: tenant.id,
        status: "open",
        synced_to_recon: false
      )

      # No mock expectation — sync_transactions should not be called
      assert :ok = ReconSyncJob.perform(%Oban.Job{args: %{}})
    end

    test "leaves synced_to_recon as false when sync fails" do
      Application.put_env(:sle, :recon_engine_enabled, true)
      Application.put_env(:sle, :recon_engine_client, SLE.Ecosystem.ReconEngineMock)

      on_exit(fn ->
        Application.put_env(:sle, :recon_engine_enabled, false)
      end)

      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          customer_id: customer.id,
          status: "paid",
          amount_paid_cents: 2999,
          paid_at: ~U[2026-04-14 10:00:00Z],
          synced_to_recon: false
        )

      expect(SLE.Ecosystem.ReconEngineMock, :sync_transactions, fn _txns ->
        {:error, :connection_refused}
      end)

      assert :ok = ReconSyncJob.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(Invoice, invoice.id)
      assert updated.synced_to_recon == false
    end

    test "returns :ok when recon engine is disabled" do
      Application.put_env(:sle, :recon_engine_enabled, false)

      tenant = insert(:tenant)

      insert(:invoice,
        tenant_id: tenant.id,
        status: "paid",
        synced_to_recon: false
      )

      # No mock expectation — should not be called
      assert :ok = ReconSyncJob.perform(%Oban.Job{args: %{}})
    end

    test "handles multiple invoices in a single batch" do
      Application.put_env(:sle, :recon_engine_enabled, true)
      Application.put_env(:sle, :recon_engine_client, SLE.Ecosystem.ReconEngineMock)

      on_exit(fn ->
        Application.put_env(:sle, :recon_engine_enabled, false)
      end)

      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, email: "bulk@example.com")

      inv1 =
        insert(:invoice,
          tenant_id: tenant.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_batch_001",
          status: "paid",
          amount_paid_cents: 1000,
          paid_at: ~U[2026-04-14 10:00:00Z],
          synced_to_recon: false
        )

      inv2 =
        insert(:invoice,
          tenant_id: tenant.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_batch_002",
          status: "paid",
          amount_paid_cents: 2000,
          paid_at: ~U[2026-04-14 11:00:00Z],
          synced_to_recon: false
        )

      expect(SLE.Ecosystem.ReconEngineMock, :sync_transactions, fn txns ->
        assert length(txns) == 2
        refs = Enum.map(txns, & &1.reference)
        assert "in_batch_001" in refs
        assert "in_batch_002" in refs
        {:ok, %{synced: 2}}
      end)

      assert :ok = ReconSyncJob.perform(%Oban.Job{args: %{}})

      assert Repo.get!(Invoice, inv1.id).synced_to_recon == true
      assert Repo.get!(Invoice, inv2.id).synced_to_recon == true
    end

    test "returns :ok when there are no unsynced invoices" do
      Application.put_env(:sle, :recon_engine_enabled, true)
      Application.put_env(:sle, :recon_engine_client, SLE.Ecosystem.ReconEngineMock)

      on_exit(fn ->
        Application.put_env(:sle, :recon_engine_enabled, false)
      end)

      # No invoices at all
      assert :ok = ReconSyncJob.perform(%Oban.Job{args: %{}})
    end
  end
end
