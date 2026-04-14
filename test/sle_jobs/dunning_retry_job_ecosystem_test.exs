defmodule SLE.Jobs.DunningRetryJobEcosystemTest do
  @moduledoc """
  Tests that DunningRetryJob emits correct ecosystem notifications
  based on attempt number escalation and recovery.
  """

  use SLE.DataCase, async: false
  use Oban.Testing, repo: SLE.Repo

  import Mox
  import SLE.Factory

  alias SLE.Jobs.DunningRetryJob

  setup :verify_on_exit!

  setup do
    Application.put_env(:sle, :notification_hub_enabled, true)
    Application.put_env(:sle, :notification_hub_client, SLE.Ecosystem.NotificationHubMock)

    on_exit(fn ->
      Application.put_env(:sle, :notification_hub_enabled, false)
    end)

    :ok
  end

  defp setup_dunning_scenario(opts \\ []) do
    status = Keyword.get(opts, :sub_status, "past_due")
    dunning_status = Keyword.get(opts, :dunning_status, "pending")
    attempt_number = Keyword.get(opts, :attempt_number, 0)
    max_attempts = Keyword.get(opts, :max_attempts, 4)

    tenant = insert(:tenant)

    customer =
      insert(:customer, tenant_id: tenant.id, email: "dunning@example.com", name: "Dunning User")

    plan = insert(:plan, tenant_id: tenant.id, name: "Pro Plan")

    subscription =
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        stripe_subscription_id: "sub_dun_eco_test",
        status: status
      )

    invoice =
      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: subscription.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_dun_eco_test",
        status: "open",
        amount_due_cents: 2999
      )

    dunning =
      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        customer_id: customer.id,
        status: dunning_status,
        attempt_number: attempt_number,
        max_attempts: max_attempts,
        notification_payload: %{"template" => "dunning.payment_failed.first"}
      )

    %{
      tenant: tenant,
      customer: customer,
      plan: plan,
      subscription: subscription,
      invoice: invoice,
      dunning: dunning
    }
  end

  describe "ecosystem emission — dunning.payment_failed escalation" do
    test "emits dunning.payment_failed.first on attempt 1 failure" do
      ctx = setup_dunning_scenario(attempt_number: 0, max_attempts: 4)

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dun_eco_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      # After failure, should emit first attempt notification
      # Then schedules next retry which also fires inline
      # We allow multiple calls for the chain
      stub(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, _payload ->
        assert event_type in [
                 "dunning.payment_failed.first",
                 "dunning.payment_failed.reminder",
                 "dunning.payment_failed.urgent",
                 "dunning.payment_failed.final_warning"
               ]

        :ok
      end)

      # Re-stub Stripe for the chain
      stub(SLE.Stripe.ClientMock, :get_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "open", amount_paid: 0}}
      end)

      stub(SLE.Stripe.ClientMock, :retry_invoice, fn "in_dun_eco_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })
    end

    test "emits correct event type for single attempt at attempt_number 0" do
      # Use max_attempts: 1 to prevent chain, directly test single emission
      ctx = setup_dunning_scenario(attempt_number: 0, max_attempts: 1)

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dun_eco_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, payload ->
        assert event_type == "dunning.payment_failed.first"
        assert payload.notification_payload != nil
        :ok
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })
    end

    test "emits dunning.payment_failed.reminder on attempt 2 (attempt_number 1)" do
      ctx = setup_dunning_scenario(attempt_number: 1, max_attempts: 2, dunning_status: "retrying")

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dun_eco_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, _payload ->
        assert event_type == "dunning.payment_failed.reminder"
        :ok
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })
    end

    test "emits dunning.payment_failed.urgent on attempt 3 (attempt_number 2)" do
      ctx = setup_dunning_scenario(attempt_number: 2, max_attempts: 3, dunning_status: "retrying")

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dun_eco_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, _payload ->
        assert event_type == "dunning.payment_failed.urgent"
        :ok
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })
    end

    test "emits dunning.payment_failed.final_warning on attempt 4 (attempt_number 3)" do
      ctx = setup_dunning_scenario(attempt_number: 3, max_attempts: 4, dunning_status: "retrying")

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dun_eco_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, _payload ->
        assert event_type == "dunning.payment_failed.final_warning"
        :ok
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })
    end
  end

  describe "ecosystem emission — dunning.recovered" do
    test "emits dunning.recovered when invoice already paid" do
      ctx = setup_dunning_scenario()

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "paid", amount_paid: 2999}}
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, payload ->
        assert event_type == "dunning.recovered"
        assert payload.notification_payload != nil
        :ok
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })
    end

    test "emits dunning.recovered when retry succeeds" do
      ctx = setup_dunning_scenario()

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dun_eco_test" ->
        {:ok, %{id: "in_dun_eco_test", status: "paid", amount_paid: 2999}}
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, _payload ->
        assert event_type == "dunning.recovered"
        :ok
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })
    end
  end
end
