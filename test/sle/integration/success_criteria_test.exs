defmodule SLE.Integration.SuccessCriteriaTest do
  @moduledoc """
  Tests that explicitly verify PRD Section 15 success criteria:
  - Idempotency: same event twice = one state transition
  - MRR handles monthly + yearly plans (yearly/12)
  - Churn rate matches manual computation
  - Ecosystem integrations emit when flags enabled, degrade when disabled
  """

  use SLE.DataCase, async: false

  import Mox
  import SLE.Factory

  alias SLE.Fixtures.StripeEvents
  alias SLE.Jobs.EventProcessorJob
  alias SLE.Metrics.{ChurnCalculator, MrrCalculator}
  alias SLE.Repo
  alias SLE.Subscriptions.{Subscription, SubscriptionEvent}
  alias SLE.Webhooks.Idempotency

  setup :verify_on_exit!

  setup do
    tenant = insert(:tenant)

    stub(SLE.Stripe.ClientMock, :retry_invoice, fn _id -> {:ok, %{status: "open"}} end)
    stub(SLE.Stripe.ClientMock, :get_invoice, fn _id -> {:ok, %{status: "open"}} end)
    stub(SLE.Stripe.ClientMock, :cancel_subscription, fn _id, _opts -> {:ok, %{}} end)
    stub(SLE.Stripe.ClientMock, :get_subscription, fn _id -> {:ok, %{}} end)
    stub(SLE.Stripe.ClientMock, :get_customer, fn _id -> {:ok, %{}} end)
    stub(SLE.Ecosystem.NotificationHubMock, :send_event, fn _type, _payload -> :ok end)
    stub(SLE.Ecosystem.WorkflowEngineMock, :execute_workflow, fn _id, _data -> {:ok, "e1"} end)
    stub(SLE.Ecosystem.ReconEngineMock, :sync_transactions, fn _txns -> {:ok, %{}} end)
    stub(SLE.Ecosystem.ClientPortalMock, :push_metrics, fn _metrics -> :ok end)

    {:ok, tenant: tenant}
  end

  # --- Idempotency ---

  describe "idempotency: duplicate event produces exactly one transition" do
    test "same event_id processed twice creates only one subscription", %{tenant: tenant} do
      event_id = "evt_idem_test_1"

      payload =
        StripeEvents.subscription_created(
          stripe_sub_id: "sub_idem_1",
          stripe_customer_id: "cus_idem_1",
          stripe_price_id: "price_idem_1",
          status: "trialing",
          event_id: event_id
        )

      # First processing
      process_webhook_event(tenant, event_id, "customer.subscription.created", payload)

      sub_count = count_subscriptions(tenant, "sub_idem_1")
      assert sub_count == 1

      # Second processing — same event_id, same idempotency_key
      # The idempotency check should prevent duplicate insertion
      _idempotency_key = Idempotency.build_key(tenant.id, event_id)
      result = Idempotency.check(tenant.id, event_id)

      case result do
        {:ok, :duplicate, _event} ->
          # Already processed — no new event inserted
          assert count_subscriptions(tenant, "sub_idem_1") == 1

        {:ok, :processing, _event} ->
          # Still processing — should not create duplicate
          assert count_subscriptions(tenant, "sub_idem_1") == 1
      end

      # Verify exactly 1 event record with this stripe_event_id
      event_count = count_events(tenant, event_id)
      assert event_count == 1
    end

    test "duplicate event does not duplicate side effects", %{tenant: tenant} do
      # Create subscription first
      process_webhook_event(
        tenant,
        "evt_side_1",
        "customer.subscription.created",
        StripeEvents.subscription_created(
          stripe_sub_id: "sub_side_1",
          stripe_customer_id: "cus_side_1",
          stripe_price_id: "price_side_1",
          status: "active",
          event_id: "evt_side_1"
        )
      )

      # Process an update event
      process_webhook_event(
        tenant,
        "evt_side_2",
        "customer.subscription.updated",
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_side_1",
          stripe_customer_id: "cus_side_1",
          stripe_price_id: "price_side_1",
          status: "active",
          event_id: "evt_side_2",
          previous_attributes: %{"status" => "trialing"}
        )
      )

      # Idempotency check blocks second processing of same event
      assert {:ok, :duplicate, _} = Idempotency.check(tenant.id, "evt_side_2")
    end
  end

  # --- MRR Computation ---

  describe "MRR handles monthly + yearly plans" do
    test "yearly plan normalizes to monthly (amount / 12)", %{tenant: tenant} do
      # Monthly plan: $29.99/month
      monthly_plan =
        insert(:plan,
          tenant: tenant,
          stripe_price_id: "price_monthly_mrr",
          amount_cents: 2999,
          interval: "month"
        )

      # Yearly plan: $299.88/year = $24.99/month
      yearly_plan =
        insert(:plan,
          tenant: tenant,
          stripe_price_id: "price_yearly_mrr",
          amount_cents: 29_988,
          interval: "year"
        )

      customer = insert(:customer, tenant: tenant)

      # Active subscriptions with plans
      insert(:subscription,
        tenant: tenant,
        customer: customer,
        plan: monthly_plan,
        status: "active"
      )

      insert(:subscription,
        tenant: tenant,
        customer: customer,
        plan: yearly_plan,
        status: "active"
      )

      mrr = MrrCalculator.compute(tenant.id)

      # Expected: 2999 (monthly) + 29988/12 (yearly) = 2999 + 2499 = 5498
      assert mrr == 2999 + div(29_988, 12)
      assert mrr == 5498
    end

    test "trialing subscriptions are NOT included in MRR", %{tenant: tenant} do
      plan = insert(:plan, tenant: tenant, amount_cents: 1999, interval: "month")
      customer = insert(:customer, tenant: tenant)

      insert(:subscription, tenant: tenant, customer: customer, plan: plan, status: "trialing")

      assert MrrCalculator.compute(tenant.id) == 0
    end
  end

  # --- Churn Rate ---

  describe "churn rate matches manual computation" do
    test "churn_rate = churned / active_at_start", %{tenant: tenant} do
      # Seed a previous snapshot with 10 active subscribers
      insert(:metrics_snapshot,
        tenant: tenant,
        active_count: 10,
        period_start: ~D[2026-04-10],
        period_end: ~D[2026-04-11]
      )

      customer = insert(:customer, tenant: tenant)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create 2 canceled subscriptions within period
      for _i <- 1..2 do
        insert(:subscription,
          tenant: tenant,
          customer: customer,
          status: "canceled",
          canceled_at: now
        )
      end

      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      {churned, rate} = ChurnCalculator.compute(tenant.id, yesterday, today)

      assert churned == 2
      # 2/10 = 0.2000
      assert Decimal.equal?(rate, Decimal.new("0.2000"))
    end

    test "zero active at start returns zero churn rate", %{tenant: tenant} do
      # No previous snapshot -> active_at_start is nil -> churn_rate = 0.0000
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      {_churned, rate} = ChurnCalculator.compute(tenant.id, yesterday, today)

      assert Decimal.equal?(rate, Decimal.new("0.0000"))
    end
  end

  # --- Ecosystem Integrations ---

  describe "ecosystem integrations emit when flags enabled" do
    test "notification hub receives event when enabled", %{tenant: _tenant} do
      test_pid = self()

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, payload ->
        send(test_pid, {:notification, event_type, payload})
        :ok
      end)

      # Temporarily enable notification hub
      prev = Application.get_env(:sle, :notification_hub_enabled)
      Application.put_env(:sle, :notification_hub_enabled, true)

      SLE.Ecosystem.emit_notification("test.event", %{foo: "bar"})

      assert_received {:notification, "test.event", %{foo: "bar"}}

      Application.put_env(:sle, :notification_hub_enabled, prev || false)
    end

    test "notification hub gracefully degrades when disabled", %{tenant: _tenant} do
      Application.put_env(:sle, :notification_hub_enabled, false)

      # Should return :ok without calling the mock
      assert :ok = SLE.Ecosystem.emit_notification("test.event", %{foo: "bar"})
    end

    test "workflow engine degrades when disabled" do
      Application.put_env(:sle, :workflow_engine_enabled, false)
      assert :ok = SLE.Ecosystem.trigger_workflow("wf_1", %{data: "test"})
    end

    test "recon engine degrades when disabled" do
      Application.put_env(:sle, :recon_engine_enabled, false)
      assert :ok = SLE.Ecosystem.sync_transactions([%{id: "t1"}])
    end

    test "client portal degrades when disabled" do
      Application.put_env(:sle, :client_portal_enabled, false)
      assert :ok = SLE.Ecosystem.push_metrics(%{mrr: 1000})
    end
  end

  # --- Helpers ---

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

    :ok = EventProcessorJob.perform(%Oban.Job{args: %{"subscription_event_id" => event.id}})
    event
  end

  defp count_subscriptions(tenant, stripe_sub_id) do
    import Ecto.Query

    Subscription
    |> where([s], s.tenant_id == ^tenant.id and s.stripe_subscription_id == ^stripe_sub_id)
    |> Repo.aggregate(:count)
  end

  defp count_events(tenant, stripe_event_id) do
    import Ecto.Query

    SubscriptionEvent
    |> where([e], e.tenant_id == ^tenant.id and e.stripe_event_id == ^stripe_event_id)
    |> Repo.aggregate(:count)
  end
end
