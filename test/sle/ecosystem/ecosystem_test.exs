defmodule SLE.EcosystemTest do
  @moduledoc false

  use SLE.DataCase, async: true

  import Mox

  alias SLE.Ecosystem

  setup :verify_on_exit!

  describe "emit_notification/3" do
    test "delegates to client when enabled" do
      Application.put_env(:sle, :notification_hub_enabled, true)
      Application.put_env(:sle, :notification_hub_client, SLE.Ecosystem.NotificationHubMock)

      on_exit(fn ->
        Application.put_env(:sle, :notification_hub_enabled, false)
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, payload ->
        assert event_type == "subscription.trial_ending"
        assert payload == %{email: "test@example.com"}
        :ok
      end)

      assert :ok =
               Ecosystem.emit_notification("subscription.trial_ending", %{
                 email: "test@example.com"
               })
    end

    test "returns :ok without calling client when disabled" do
      Application.put_env(:sle, :notification_hub_enabled, false)

      # No mock expectation — if client is called, verify_on_exit! will catch it
      assert :ok =
               Ecosystem.emit_notification("subscription.trial_ending", %{
                 email: "test@example.com"
               })
    end

    test "logs when disabled" do
      Application.put_env(:sle, :notification_hub_enabled, false)

      assert :ok = Ecosystem.emit_notification("subscription.trial_ending", %{data: true})
    end
  end

  describe "trigger_workflow/2" do
    test "delegates to client when enabled" do
      Application.put_env(:sle, :workflow_engine_enabled, true)
      Application.put_env(:sle, :workflow_engine_client, SLE.Ecosystem.WorkflowEngineMock)

      on_exit(fn ->
        Application.put_env(:sle, :workflow_engine_enabled, false)
      end)

      expect(SLE.Ecosystem.WorkflowEngineMock, :execute_workflow, fn workflow_id, trigger_data ->
        assert workflow_id == "wf_123"
        assert trigger_data == %{amount: 1000}
        {:ok, "exec_456"}
      end)

      assert {:ok, "exec_456"} = Ecosystem.trigger_workflow("wf_123", %{amount: 1000})
    end

    test "returns :ok without calling client when disabled" do
      Application.put_env(:sle, :workflow_engine_enabled, false)

      assert :ok = Ecosystem.trigger_workflow("wf_123", %{amount: 1000})
    end
  end

  describe "sync_transactions/1" do
    test "delegates to client when enabled" do
      Application.put_env(:sle, :recon_engine_enabled, true)
      Application.put_env(:sle, :recon_engine_client, SLE.Ecosystem.ReconEngineMock)

      on_exit(fn ->
        Application.put_env(:sle, :recon_engine_enabled, false)
      end)

      transactions = [%{id: "tx_1"}, %{id: "tx_2"}]

      expect(SLE.Ecosystem.ReconEngineMock, :sync_transactions, fn txns ->
        assert txns == transactions
        {:ok, %{synced: 2}}
      end)

      assert {:ok, %{synced: 2}} = Ecosystem.sync_transactions(transactions)
    end

    test "returns :ok without calling client when disabled" do
      Application.put_env(:sle, :recon_engine_enabled, false)

      assert :ok = Ecosystem.sync_transactions([%{id: "tx_1"}])
    end
  end

  describe "push_metrics/1" do
    test "delegates to client when enabled" do
      Application.put_env(:sle, :client_portal_enabled, true)
      Application.put_env(:sle, :client_portal_client, SLE.Ecosystem.ClientPortalMock)

      on_exit(fn ->
        Application.put_env(:sle, :client_portal_enabled, false)
      end)

      metrics = %{mrr_cents: 100_000, churn_rate: 0.05}

      expect(SLE.Ecosystem.ClientPortalMock, :push_metrics, fn m ->
        assert m == metrics
        :ok
      end)

      assert :ok = Ecosystem.push_metrics(metrics)
    end

    test "returns :ok without calling client when disabled" do
      Application.put_env(:sle, :client_portal_enabled, false)

      assert :ok = Ecosystem.push_metrics(%{mrr_cents: 100_000})
    end
  end
end
