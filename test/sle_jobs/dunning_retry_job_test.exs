defmodule SLE.Jobs.DunningRetryJobTest do
  @moduledoc false

  use SLE.DataCase, async: true
  use Oban.Testing, repo: SLE.Repo

  import Mox
  import SLE.Factory

  alias SLE.Dunning.DunningAttempt
  alias SLE.Jobs.DunningRetryJob

  setup :verify_on_exit!

  defp setup_dunning_scenario(opts \\ []) do
    status = Keyword.get(opts, :sub_status, "past_due")
    dunning_status = Keyword.get(opts, :dunning_status, "pending")
    attempt_number = Keyword.get(opts, :attempt_number, 0)
    max_attempts = Keyword.get(opts, :max_attempts, 4)

    tenant = insert(:tenant)
    customer = insert(:customer, tenant_id: tenant.id)
    plan = insert(:plan, tenant_id: tenant.id)

    subscription =
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        stripe_subscription_id: "sub_dunning_test",
        status: status
      )

    invoice =
      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: subscription.id,
        customer_id: customer.id,
        stripe_invoice_id: "in_dunning_test",
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
      subscription: subscription,
      invoice: invoice,
      dunning: dunning
    }
  end

  describe "perform/1 — invoice already paid" do
    test "recovers dunning when Stripe reports invoice as paid" do
      ctx = setup_dunning_scenario()

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dunning_test" ->
        {:ok, %{id: "in_dunning_test", status: "paid", amount_paid: 2999}}
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })

      reloaded = Repo.get!(DunningAttempt, ctx.dunning.id)
      assert reloaded.status == "recovered"
      assert reloaded.recovery_amount == 2999
    end
  end

  describe "perform/1 — retry succeeds" do
    test "recovers dunning and transitions subscription to active" do
      ctx = setup_dunning_scenario()

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dunning_test" ->
        {:ok, %{id: "in_dunning_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dunning_test" ->
        {:ok, %{id: "in_dunning_test", status: "paid", amount_paid: 2999}}
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })

      reloaded = Repo.get!(DunningAttempt, ctx.dunning.id)
      assert reloaded.status == "recovered"
      assert reloaded.recovery_amount == 2999

      reloaded_sub = Repo.get!(SLE.Subscriptions.Subscription, ctx.subscription.id)
      assert reloaded_sub.status == "active"
    end
  end

  describe "perform/1 — retry fails" do
    test "advances dunning and exhausts when all retries fail" do
      # With inline Oban testing, enqueued retry jobs execute immediately,
      # causing the full retry chain to play out. We use stub to allow
      # unlimited calls and verify the final exhausted state.
      ctx = setup_dunning_scenario(attempt_number: 0, max_attempts: 4)

      stub(SLE.Stripe.ClientMock, :get_invoice, fn "in_dunning_test" ->
        {:ok, %{id: "in_dunning_test", status: "open", amount_paid: 0}}
      end)

      stub(SLE.Stripe.ClientMock, :retry_invoice, fn "in_dunning_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })

      reloaded = Repo.get!(DunningAttempt, ctx.dunning.id)
      # After full chain plays out: exhausted (4 attempts reached max_attempts=4)
      assert reloaded.status == "exhausted"
      assert reloaded.attempt_number == 4
      assert length(reloaded.error_log) == 4
    end

    test "advances dunning attempt on single failure (max_attempts: 1 + start at 0)" do
      # Start at attempt 3/4 so only one retry remains before exhaustion
      ctx = setup_dunning_scenario(attempt_number: 3, max_attempts: 4, dunning_status: "retrying")

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dunning_test" ->
        {:ok, %{id: "in_dunning_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dunning_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })

      reloaded = Repo.get!(DunningAttempt, ctx.dunning.id)
      assert reloaded.status == "exhausted"
      assert reloaded.attempt_number == 4
    end

    test "records error info in error_log" do
      ctx = setup_dunning_scenario(attempt_number: 3, max_attempts: 4, dunning_status: "retrying")

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dunning_test" ->
        {:ok, %{id: "in_dunning_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dunning_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      DunningRetryJob.perform(%Oban.Job{
        args: %{
          "dunning_attempt_id" => ctx.dunning.id,
          "tenant_id" => ctx.tenant.id
        }
      })

      reloaded = Repo.get!(DunningAttempt, ctx.dunning.id)
      assert length(reloaded.error_log) >= 1
      [last_error | _] = Enum.reverse(reloaded.error_log)
      assert Map.has_key?(last_error, "error")
    end
  end

  describe "perform/1 — max attempts exhausted" do
    test "exhausts dunning when max attempts reached" do
      ctx = setup_dunning_scenario(attempt_number: 3, max_attempts: 4, dunning_status: "retrying")

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dunning_test" ->
        {:ok, %{id: "in_dunning_test", status: "open", amount_paid: 0}}
      end)
      |> expect(:retry_invoice, fn "in_dunning_test" ->
        {:error, {:payment_failed, "Card declined"}}
      end)

      assert :ok =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })

      reloaded = Repo.get!(DunningAttempt, ctx.dunning.id)
      assert reloaded.status == "exhausted"
    end
  end

  describe "perform/1 — error handling" do
    test "returns error when dunning attempt not found" do
      fake_id = Ecto.UUID.generate()
      tenant_id = Ecto.UUID.generate()

      assert {:error, :dunning_not_found} =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => fake_id,
                   "tenant_id" => tenant_id
                 }
               })
    end

    test "returns error when Stripe get_invoice fails" do
      ctx = setup_dunning_scenario()

      SLE.Stripe.ClientMock
      |> expect(:get_invoice, fn "in_dunning_test" ->
        {:error, {:stripe_error, "Service unavailable"}}
      end)

      assert {:error, {:stripe_error, "Service unavailable"}} =
               DunningRetryJob.perform(%Oban.Job{
                 args: %{
                   "dunning_attempt_id" => ctx.dunning.id,
                   "tenant_id" => ctx.tenant.id
                 }
               })
    end
  end
end
