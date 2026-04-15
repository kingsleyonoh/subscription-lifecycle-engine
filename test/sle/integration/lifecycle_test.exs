defmodule SLE.Integration.LifecycleTest do
  @moduledoc """
  Integration test simulating the full subscription lifecycle
  through the webhook handler + event processor pipeline.

  Uses real database, real event processing (Oban inline mode),
  and mocked Stripe API calls.
  """

  use SLE.DataCase, async: false

  import Mox
  import SLE.Factory

  alias SLE.Fixtures.StripeEvents
  alias SLE.Jobs.EventProcessorJob
  alias SLE.Repo
  alias SLE.Subscriptions.{Subscription, SubscriptionEvent}
  alias SLE.Webhooks.Idempotency

  setup :verify_on_exit!

  @stripe_sub_id "sub_lifecycle_test_1"
  @stripe_customer_id "cus_lifecycle_test_1"
  @stripe_price_id "price_lifecycle_test_1"
  @stripe_invoice_id "in_lifecycle_test_1"

  setup do
    tenant = insert(:tenant)

    # Allow mocks for this test process (Oban inline runs in same process)
    stub(SLE.Stripe.ClientMock, :retry_invoice, fn _id -> {:ok, %{status: "open"}} end)
    stub(SLE.Stripe.ClientMock, :get_invoice, fn _id -> {:ok, %{status: "open"}} end)
    stub(SLE.Stripe.ClientMock, :cancel_subscription, fn _id, _opts -> {:ok, %{}} end)
    stub(SLE.Stripe.ClientMock, :get_subscription, fn _id -> {:ok, %{}} end)
    stub(SLE.Stripe.ClientMock, :get_customer, fn _id -> {:ok, %{}} end)

    # Stub ecosystem mocks (notifications disabled by default in test)
    stub(SLE.Ecosystem.NotificationHubMock, :send_event, fn _type, _payload -> :ok end)

    stub(SLE.Ecosystem.WorkflowEngineMock, :execute_workflow, fn _id, _data -> {:ok, "exec_1"} end)

    stub(SLE.Ecosystem.ReconEngineMock, :sync_transactions, fn _txns -> {:ok, %{}} end)
    stub(SLE.Ecosystem.ClientPortalMock, :push_metrics, fn _metrics -> :ok end)

    {:ok, tenant: tenant}
  end

  describe "happy path: trialing -> active -> past_due -> recovered -> canceled" do
    test "full lifecycle with recovery", %{tenant: tenant} do
      # Step 1: subscription.created (trialing)
      sub = create_subscription_via_webhook(tenant, "trialing", "evt_created_1")
      assert sub.status == "trialing"

      # Step 2: subscription.updated (active)
      sub =
        update_subscription_via_webhook(tenant, "active", "evt_updated_active_1",
          previous_attributes: %{"status" => "trialing"}
        )

      assert sub.status == "active"

      # Step 3: Create an invoice (payment_failed scenario)
      create_invoice_via_webhook(tenant, "open", "evt_inv_created_1")

      # Step 4: subscription.updated (past_due) — triggers dunning
      sub =
        update_subscription_via_webhook(tenant, "past_due", "evt_updated_pastdue_1",
          previous_attributes: %{"status" => "active"}
        )

      assert sub.status == "past_due"
      assert_dunning_created(tenant)

      # Step 5: invoice.paid — triggers dunning recovery + subscription back to active
      pay_invoice_via_webhook(tenant, "evt_inv_paid_1")
      sub = get_subscription(tenant)
      assert sub.status == "active"
      assert_dunning_recovered(tenant)

      # Step 6: subscription.deleted (canceled)
      cancel_subscription_via_webhook(tenant, "evt_deleted_1")
      sub = get_subscription(tenant)
      assert sub.status == "canceled"
    end
  end

  describe "churned path: trialing -> active -> past_due -> exhausted -> canceled" do
    test "full churn lifecycle", %{tenant: tenant} do
      # Step 1: subscription.created (trialing)
      create_subscription_via_webhook(tenant, "trialing", "evt_churn_created_1")

      # Step 2: activate
      update_subscription_via_webhook(tenant, "active", "evt_churn_active_1",
        previous_attributes: %{"status" => "trialing"}
      )

      # Step 3: Create invoice
      create_invoice_via_webhook(tenant, "open", "evt_churn_inv_1")

      # Step 4: Go past_due — dunning is created and auto-exhausted
      # (Oban inline mode causes DunningRetryJob to run all retries immediately)
      update_subscription_via_webhook(tenant, "past_due", "evt_churn_pastdue_1",
        previous_attributes: %{"status" => "active"}
      )

      assert_dunning_created(tenant)

      # Verify dunning reached exhausted state after inline retry cycles
      dunning = get_dunning(tenant)
      assert dunning.status == "exhausted"

      # Step 5: Cancel subscription via webhook (after escalation)
      cancel_subscription_via_webhook(tenant, "evt_churn_deleted_1")
      sub = get_subscription(tenant)
      assert sub.status == "canceled"
    end
  end

  # --- Helper Functions ---

  defp create_subscription_via_webhook(tenant, status, event_id) do
    payload =
      StripeEvents.subscription_created(
        stripe_sub_id: @stripe_sub_id,
        stripe_customer_id: @stripe_customer_id,
        stripe_price_id: @stripe_price_id,
        status: status,
        event_id: event_id,
        trial_start: System.system_time(:second),
        trial_end: System.system_time(:second) + 14 * 86_400
      )

    process_webhook_event(tenant, event_id, "customer.subscription.created", payload)
    get_subscription(tenant)
  end

  defp update_subscription_via_webhook(tenant, new_status, event_id, opts) do
    payload =
      StripeEvents.subscription_updated(
        stripe_sub_id: @stripe_sub_id,
        stripe_customer_id: @stripe_customer_id,
        stripe_price_id: @stripe_price_id,
        status: new_status,
        event_id: event_id,
        previous_attributes: Keyword.get(opts, :previous_attributes, %{})
      )

    process_webhook_event(tenant, event_id, "customer.subscription.updated", payload)
    get_subscription(tenant)
  end

  defp create_invoice_via_webhook(tenant, status, event_id) do
    payload =
      StripeEvents.invoice_event("invoice.created",
        stripe_invoice_id: @stripe_invoice_id,
        stripe_customer_id: @stripe_customer_id,
        stripe_subscription_id: @stripe_sub_id,
        status: status,
        amount_due: 2999,
        event_id: event_id
      )

    process_webhook_event(tenant, event_id, "invoice.created", payload)
  end

  defp pay_invoice_via_webhook(tenant, event_id) do
    payload =
      StripeEvents.invoice_event("invoice.paid",
        stripe_invoice_id: @stripe_invoice_id,
        stripe_customer_id: @stripe_customer_id,
        stripe_subscription_id: @stripe_sub_id,
        status: "paid",
        amount_due: 2999,
        amount_paid: 2999,
        paid_at: System.system_time(:second),
        event_id: event_id
      )

    process_webhook_event(tenant, event_id, "invoice.paid", payload)
  end

  defp cancel_subscription_via_webhook(tenant, event_id) do
    payload =
      StripeEvents.subscription_deleted(
        stripe_sub_id: @stripe_sub_id,
        stripe_customer_id: @stripe_customer_id,
        stripe_price_id: @stripe_price_id,
        event_id: event_id,
        canceled_at: System.system_time(:second),
        ended_at: System.system_time(:second)
      )

    process_webhook_event(tenant, event_id, "customer.subscription.deleted", payload)
  end

  defp process_webhook_event(tenant, stripe_event_id, event_type, payload) do
    idempotency_key = Idempotency.build_key(tenant.id, stripe_event_id)

    {:ok, event} =
      %SubscriptionEvent{}
      |> SubscriptionEvent.changeset(%{
        tenant_id: tenant.id,
        stripe_event_id: stripe_event_id,
        event_type: event_type,
        payload: payload,
        idempotency_key: idempotency_key
      })
      |> Repo.insert()

    # Process inline (Oban inline mode)
    :ok = EventProcessorJob.perform(%Oban.Job{args: %{"subscription_event_id" => event.id}})
    event
  end

  defp get_subscription(tenant) do
    import Ecto.Query

    Subscription
    |> where([s], s.tenant_id == ^tenant.id and s.stripe_subscription_id == ^@stripe_sub_id)
    |> Repo.one!()
  end

  defp assert_dunning_created(tenant) do
    import Ecto.Query

    count =
      SLE.Dunning.DunningAttempt
      |> where([d], d.tenant_id == ^tenant.id)
      |> Repo.aggregate(:count)

    assert count > 0, "Expected dunning attempt to be created"
  end

  defp assert_dunning_recovered(tenant) do
    import Ecto.Query

    dunning =
      SLE.Dunning.DunningAttempt
      |> where([d], d.tenant_id == ^tenant.id and d.status == "recovered")
      |> Repo.one()

    assert dunning != nil, "Expected dunning attempt to be recovered"
  end

  defp get_dunning(tenant) do
    import Ecto.Query

    SLE.Dunning.DunningAttempt
    |> where([d], d.tenant_id == ^tenant.id)
    |> Repo.one!()
  end
end
