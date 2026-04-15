defmodule SLE.Jobs.TrialEndingCheckJobTest do
  @moduledoc false

  use SLE.DataCase, async: false
  use Oban.Testing, repo: SLE.Repo

  import Mox
  import SLE.Factory

  alias SLE.Jobs.TrialEndingCheckJob
  alias SLE.Subscriptions.Subscription

  setup :verify_on_exit!

  setup do
    Application.put_env(:sle, :notification_hub_enabled, true)
    Application.put_env(:sle, :notification_hub_client, SLE.Ecosystem.NotificationHubMock)

    on_exit(fn ->
      Application.put_env(:sle, :notification_hub_enabled, false)
    end)

    :ok
  end

  describe "perform/1" do
    test "notifies subscriptions with trial ending within 3 days" do
      tenant = insert(:tenant)

      customer =
        insert(:customer, tenant_id: tenant.id, email: "trial@example.com", name: "Trial User")

      plan = insert(:plan, tenant_id: tenant.id, name: "Pro Plan")

      # Trial ending in 2 days — should be notified
      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          status: "trialing",
          trial_end: DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second),
          trial_ending_notified: false
        )

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, fn event_type, payload ->
        assert event_type == "subscription.trial_ending"
        assert payload.email == "trial@example.com"
        assert payload.customer_name == "Trial User"
        assert payload.plan_name == "Pro Plan"
        assert payload.subscription_id == sub.id
        :ok
      end)

      assert :ok = TrialEndingCheckJob.perform(%Oban.Job{args: %{}})

      # Verify trial_ending_notified was set to true
      updated = Repo.get!(Subscription, sub.id)
      assert updated.trial_ending_notified == true
    end

    test "skips subscriptions already notified" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "trialing",
        trial_end: DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second),
        trial_ending_notified: true
      )

      # No mock expectation — if send_event is called, verify_on_exit! will catch it
      assert :ok = TrialEndingCheckJob.perform(%Oban.Job{args: %{}})
    end

    test "skips subscriptions with trial ending more than 3 days out" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "trialing",
        trial_end: DateTime.utc_now() |> DateTime.add(5, :day) |> DateTime.truncate(:second),
        trial_ending_notified: false
      )

      # No mock expectation — should not be notified
      assert :ok = TrialEndingCheckJob.perform(%Oban.Job{args: %{}})
    end

    test "skips non-trialing subscriptions" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "active",
        trial_end: DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second),
        trial_ending_notified: false
      )

      # No mock expectation — active subscription should not be notified
      assert :ok = TrialEndingCheckJob.perform(%Oban.Job{args: %{}})
    end

    test "skips subscriptions with nil trial_end" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "trialing",
        trial_end: nil,
        trial_ending_notified: false
      )

      # No mock expectation — nil trial_end should not match
      assert :ok = TrialEndingCheckJob.perform(%Oban.Job{args: %{}})
    end

    test "handles multiple eligible subscriptions across tenants" do
      tenant1 = insert(:tenant)
      customer1 = insert(:customer, tenant_id: tenant1.id, email: "c1@example.com", name: "C1")
      plan1 = insert(:plan, tenant_id: tenant1.id, name: "Plan A")

      tenant2 = insert(:tenant)
      customer2 = insert(:customer, tenant_id: tenant2.id, email: "c2@example.com", name: "C2")
      plan2 = insert(:plan, tenant_id: tenant2.id, name: "Plan B")

      insert(:subscription,
        tenant_id: tenant1.id,
        customer_id: customer1.id,
        plan_id: plan1.id,
        status: "trialing",
        trial_end: DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second),
        trial_ending_notified: false
      )

      insert(:subscription,
        tenant_id: tenant2.id,
        customer_id: customer2.id,
        plan_id: plan2.id,
        status: "trialing",
        trial_end: DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second),
        trial_ending_notified: false
      )

      expect(SLE.Ecosystem.NotificationHubMock, :send_event, 2, fn _event_type, _payload ->
        :ok
      end)

      assert :ok = TrialEndingCheckJob.perform(%Oban.Job{args: %{}})

      # Both should be marked notified
      subs = Repo.all(from s in Subscription, where: s.trial_ending_notified == true)
      assert length(subs) == 2
    end

    test "returns :ok even when no eligible subscriptions exist" do
      assert :ok = TrialEndingCheckJob.perform(%Oban.Job{args: %{}})
    end
  end
end
