defmodule SLE.Jobs.DunningEscalationJobEcosystemTest do
  @moduledoc """
  Tests that DunningEscalationJob emits subscription.churned
  notification after canceling subscription due to dunning exhaustion.
  """

  use SLE.DataCase, async: false
  use Oban.Testing, repo: SLE.Repo

  import Mox
  import SLE.Factory

  alias SLE.Jobs.DunningEscalationJob

  setup :verify_on_exit!

  setup do
    Application.put_env(:sle, :notification_hub_enabled, true)
    Application.put_env(:sle, :notification_hub_client, SLE.Ecosystem.NotificationHubMock)

    on_exit(fn ->
      Application.put_env(:sle, :notification_hub_enabled, false)
    end)

    :ok
  end

  defp setup_exhausted_dunning do
    tenant = insert(:tenant)

    customer =
      insert(:customer, tenant_id: tenant.id, email: "churned@example.com", name: "Churned User")

    plan = insert(:plan, tenant_id: tenant.id, name: "Pro Plan", amount_cents: 4999)

    subscription =
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        stripe_subscription_id: "sub_esc_eco_test",
        status: "past_due"
      )

    invoice =
      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: subscription.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_esc_eco_test",
        status: "open",
        amount_due_cents: 4999
      )

    dunning =
      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        customer_id: customer.id,
        status: "exhausted",
        attempt_number: 4,
        max_attempts: 4,
        notification_payload: %{"template" => "dunning.payment_failed.final_warning"}
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

  describe "ecosystem emission — subscription.churned" do
    test "emits subscription.churned after canceling subscription" do
      _ctx = setup_exhausted_dunning()

      SLE.Stripe.ClientMock
      |> expect(:cancel_subscription, fn "sub_esc_eco_test", [cancel_at_period_end: false] ->
        {:ok, %{id: "sub_esc_eco_test", status: "canceled"}}
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, payload ->
        assert event_type == "subscription.churned"
        assert payload.customer_email == "churned@example.com"
        assert payload.customer_name == "Churned User"
        assert payload.plan_name == "Pro Plan"
        assert payload.amount_due == 4999
        assert payload.dunning_attempt_count == 4
        :ok
      end)

      assert :ok = DunningEscalationJob.perform(%Oban.Job{args: %{}})
    end

    test "does not emit notification when Stripe cancel fails" do
      _ctx = setup_exhausted_dunning()

      SLE.Stripe.ClientMock
      |> expect(:cancel_subscription, fn "sub_esc_eco_test", [cancel_at_period_end: false] ->
        {:error, {:stripe_error, "Service unavailable"}}
      end)

      # No send_event expect — verify_on_exit! will catch unexpected calls

      assert :ok = DunningEscalationJob.perform(%Oban.Job{args: %{}})
    end

    test "emits notification for each canceled subscription" do
      _ctx1 = setup_exhausted_dunning()

      tenant2 = insert(:tenant)

      customer2 =
        insert(:customer,
          tenant_id: tenant2.id,
          email: "churned2@example.com",
          name: "Churned User 2"
        )

      plan2 = insert(:plan, tenant_id: tenant2.id, name: "Basic Plan", amount_cents: 999)

      sub2 =
        insert(:subscription,
          tenant_id: tenant2.id,
          customer_id: customer2.id,
          plan_id: plan2.id,
          stripe_subscription_id: "sub_esc_eco_test_2",
          status: "past_due"
        )

      invoice2 =
        insert(:invoice,
          tenant_id: tenant2.id,
          subscription_id: sub2.id,
          customer_id: customer2.id,
          stripe_invoice_id: "in_esc_eco_test_2",
          status: "open",
          amount_due_cents: 999
        )

      _dunning2 =
        insert(:dunning_attempt,
          tenant_id: tenant2.id,
          subscription_id: sub2.id,
          invoice_id: invoice2.id,
          customer_id: customer2.id,
          status: "exhausted",
          attempt_number: 4,
          max_attempts: 4,
          notification_payload: %{"template" => "dunning.payment_failed.final_warning"}
        )

      SLE.Stripe.ClientMock
      |> expect(:cancel_subscription, fn "sub_esc_eco_test", [cancel_at_period_end: false] ->
        {:ok, %{id: "sub_esc_eco_test", status: "canceled"}}
      end)
      |> expect(:cancel_subscription, fn "sub_esc_eco_test_2", [cancel_at_period_end: false] ->
        {:ok, %{id: "sub_esc_eco_test_2", status: "canceled"}}
      end)

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, 2, fn event_type, _payload ->
        assert event_type == "subscription.churned"
        :ok
      end)

      assert :ok = DunningEscalationJob.perform(%Oban.Job{args: %{}})
    end
  end
end
