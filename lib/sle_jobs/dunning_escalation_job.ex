defmodule SLE.Jobs.DunningEscalationJob do
  @moduledoc """
  Oban cron worker that processes exhausted dunning attempts.

  Runs hourly on the `:dunning` queue. For each exhausted dunning:
    1. Cancel the Stripe subscription immediately
    2. Mark the dunning attempt as canceled
    3. Transition the local subscription to canceled

  Queue: `:dunning`, max attempts: 1.
  """

  use Oban.Worker, queue: :dunning, max_attempts: 1

  require Logger

  import Ecto.Query

  alias SLE.Dunning
  alias SLE.Dunning.DunningAttempt
  alias SLE.Ecosystem
  alias SLE.Repo
  alias SLE.Subscriptions

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    exhausted_attempts =
      DunningAttempt
      |> where([d], d.status == "exhausted")
      |> preload([:subscription, :customer, :invoice, subscription: [:plan]])
      |> Repo.all()

    Enum.each(exhausted_attempts, &process_exhausted/1)

    :ok
  end

  defp process_exhausted(dunning) do
    stripe_sub_id = dunning.subscription.stripe_subscription_id

    case stripe_client().cancel_subscription(stripe_sub_id, cancel_at_period_end: false) do
      {:ok, _result} ->
        Dunning.cancel(dunning.tenant_id, dunning.id)
        Subscriptions.transition(dunning.tenant_id, dunning.subscription_id, "canceled")
        emit_churn_notification(dunning)

        Logger.info(
          "DunningEscalationJob: canceled subscription #{stripe_sub_id} " <>
            "for dunning #{dunning.id}"
        )

      {:error, reason} ->
        Logger.error(
          "DunningEscalationJob: failed to cancel subscription #{stripe_sub_id}: " <>
            "#{inspect(reason)}"
        )
    end
  end

  defp stripe_client do
    Application.get_env(:sle, :stripe_client)
  end

  defp emit_churn_notification(dunning) do
    payload = %{
      customer_email: if(dunning.customer, do: dunning.customer.email),
      customer_name: if(dunning.customer, do: dunning.customer.name),
      plan_name: if(dunning.subscription.plan, do: dunning.subscription.plan.name),
      amount_due: if(dunning.invoice, do: dunning.invoice.amount_due_cents),
      dunning_attempt_count: dunning.attempt_number
    }

    Ecosystem.emit_notification("subscription.churned", payload)
  end
end
