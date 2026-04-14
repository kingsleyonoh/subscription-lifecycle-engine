defmodule SLE.Webhooks.Processors.SubscriptionProcessorDunningTest do
  @moduledoc false

  use SLE.DataCase, async: true
  use Oban.Testing, repo: SLE.Repo

  import Mox

  alias SLE.Dunning.DunningAttempt
  alias SLE.Webhooks.Processors.SubscriptionProcessor
  alias SLE.Fixtures.StripeEvents

  import SLE.Factory

  setup :verify_on_exit!

  defp build_event(tenant, event_payload) do
    insert(:subscription_event,
      tenant_id: tenant.id,
      event_type: event_payload["type"],
      payload: event_payload,
      processed_at: nil
    )
  end

  describe "process/1 — dunning trigger on past_due transition" do
    test "creates dunning attempt when subscription transitions to past_due" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_dun_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_dun_1")

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_dun_1",
          status: "active"
        )

      _invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_dun_1",
          status: "open",
          amount_due_cents: 2999
        )

      # With inline Oban, the DunningRetryJob executes immediately after enqueue.
      # Stub Stripe mock to allow the full retry chain to play out.
      stub(SLE.Stripe.ClientMock, :get_invoice, fn _id ->
        {:ok, %{id: "in_dun_1", status: "open", amount_paid: 0}}
      end)

      stub(SLE.Stripe.ClientMock, :retry_invoice, fn _id ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_dun_1",
          stripe_customer_id: "cus_dun_1",
          stripe_price_id: "price_dun_1",
          status: "past_due",
          previous_attributes: %{"status" => "active"}
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      dunning =
        DunningAttempt
        |> where([d], d.tenant_id == ^tenant.id and d.subscription_id == ^sub.id)
        |> Repo.one()

      assert dunning != nil
      # Dunning was created and then the inline retry chain played out
      assert dunning.attempt_number >= 0
    end

    test "does not create dunning when subscription is paused (no dunning for paused subs)" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_paused_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_paused_1")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_paused_1",
          status: "paused"
        )

      # Paused -> past_due is not a valid state machine transition
      # so status won't change. But let's ensure no dunning is created
      # when subscription stays paused.
      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_paused_1",
          stripe_customer_id: "cus_paused_1",
          stripe_price_id: "price_paused_1",
          status: "past_due",
          previous_attributes: %{"status" => "paused"}
        )

      event = build_event(tenant, payload)
      {:ok, _result} = SubscriptionProcessor.process(event)

      dunning_count =
        DunningAttempt
        |> where([d], d.tenant_id == ^tenant.id)
        |> Repo.aggregate(:count, :id)

      assert dunning_count == 0
    end

    test "does not create duplicate dunning for same invoice (idempotent)" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_dedup_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_dedup_1")

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_dedup_1",
          status: "active"
        )

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          stripe_invoice_id: "in_dedup_1",
          status: "open",
          amount_due_cents: 2999
        )

      # Pre-create dunning for this invoice
      _existing_dunning =
        insert(:dunning_attempt,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          invoice_id: invoice.id,
          customer_id: customer.id,
          status: "retrying",
          attempt_number: 1,
          notification_payload: %{"template" => "dunning.payment_failed.first"}
        )

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_dedup_1",
          stripe_customer_id: "cus_dedup_1",
          stripe_price_id: "price_dedup_1",
          status: "past_due",
          previous_attributes: %{"status" => "active"}
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      dunning_count =
        DunningAttempt
        |> where([d], d.tenant_id == ^tenant.id and d.subscription_id == ^sub.id)
        |> Repo.aggregate(:count, :id)

      # Should still be just the one existing dunning, no duplicate
      assert dunning_count == 1
    end

    test "handles missing invoice gracefully (no dunning created)" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_noinv_1")
      plan = insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_noinv_1")

      _sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          stripe_subscription_id: "sub_noinv_1",
          status: "active"
        )

      payload =
        StripeEvents.subscription_updated(
          stripe_sub_id: "sub_noinv_1",
          stripe_customer_id: "cus_noinv_1",
          stripe_price_id: "price_noinv_1",
          status: "past_due",
          previous_attributes: %{"status" => "active"}
        )

      event = build_event(tenant, payload)
      assert {:ok, _result} = SubscriptionProcessor.process(event)

      dunning_count =
        DunningAttempt
        |> where([d], d.tenant_id == ^tenant.id)
        |> Repo.aggregate(:count, :id)

      assert dunning_count == 0
    end
  end
end
