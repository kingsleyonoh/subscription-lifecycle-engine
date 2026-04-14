defmodule SLE.Jobs.DunningEscalationJobTest do
  @moduledoc false

  use SLE.DataCase, async: true
  use Oban.Testing, repo: SLE.Repo

  import Mox
  import SLE.Factory

  alias SLE.Dunning.DunningAttempt
  alias SLE.Jobs.DunningEscalationJob
  alias SLE.Subscriptions.Subscription

  setup :verify_on_exit!

  defp setup_exhausted_dunning do
    tenant = insert(:tenant)
    customer = insert(:customer, tenant_id: tenant.id)
    plan = insert(:plan, tenant_id: tenant.id)

    subscription =
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        stripe_subscription_id: "sub_esc_test",
        status: "past_due"
      )

    invoice =
      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: subscription.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_esc_test",
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
      subscription: subscription,
      invoice: invoice,
      dunning: dunning
    }
  end

  describe "perform/1 — cancels exhausted dunning attempts" do
    test "cancels subscription via Stripe and marks dunning as canceled" do
      ctx = setup_exhausted_dunning()

      SLE.Stripe.ClientMock
      |> expect(:cancel_subscription, fn "sub_esc_test", [cancel_at_period_end: false] ->
        {:ok, %{id: "sub_esc_test", status: "canceled"}}
      end)

      assert :ok =
               DunningEscalationJob.perform(%Oban.Job{args: %{}})

      reloaded_dunning = Repo.get!(DunningAttempt, ctx.dunning.id)
      assert reloaded_dunning.status == "canceled"

      reloaded_sub = Repo.get!(Subscription, ctx.subscription.id)
      assert reloaded_sub.status == "canceled"
    end

    test "processes multiple exhausted dunning attempts" do
      ctx1 = setup_exhausted_dunning()

      tenant2 = insert(:tenant)
      customer2 = insert(:customer, tenant_id: tenant2.id)
      plan2 = insert(:plan, tenant_id: tenant2.id)

      sub2 =
        insert(:subscription,
          tenant_id: tenant2.id,
          customer_id: customer2.id,
          plan_id: plan2.id,
          stripe_subscription_id: "sub_esc_test_2",
          status: "past_due"
        )

      invoice2 =
        insert(:invoice,
          tenant_id: tenant2.id,
          subscription_id: sub2.id,
          customer_id: customer2.id,
          stripe_invoice_id: "in_esc_test_2",
          status: "open",
          amount_due_cents: 3999
        )

      dunning2 =
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
      |> expect(:cancel_subscription, fn "sub_esc_test", [cancel_at_period_end: false] ->
        {:ok, %{id: "sub_esc_test", status: "canceled"}}
      end)
      |> expect(:cancel_subscription, fn "sub_esc_test_2", [cancel_at_period_end: false] ->
        {:ok, %{id: "sub_esc_test_2", status: "canceled"}}
      end)

      assert :ok = DunningEscalationJob.perform(%Oban.Job{args: %{}})

      assert Repo.get!(DunningAttempt, ctx1.dunning.id).status == "canceled"
      assert Repo.get!(DunningAttempt, dunning2.id).status == "canceled"
      assert Repo.get!(Subscription, ctx1.subscription.id).status == "canceled"
      assert Repo.get!(Subscription, sub2.id).status == "canceled"
    end

    test "handles no exhausted dunning attempts gracefully" do
      assert :ok = DunningEscalationJob.perform(%Oban.Job{args: %{}})
    end

    test "continues processing remaining attempts when Stripe cancel fails for one" do
      ctx = setup_exhausted_dunning()

      SLE.Stripe.ClientMock
      |> expect(:cancel_subscription, fn "sub_esc_test", [cancel_at_period_end: false] ->
        {:error, {:stripe_error, "Service unavailable"}}
      end)

      assert :ok = DunningEscalationJob.perform(%Oban.Job{args: %{}})

      # Dunning should NOT be canceled since Stripe failed
      reloaded = Repo.get!(DunningAttempt, ctx.dunning.id)
      assert reloaded.status == "exhausted"
    end
  end
end
