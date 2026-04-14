defmodule SLE.Jobs.TrialEndingCheckJob do
  @moduledoc """
  Oban cron worker that checks for trial subscriptions ending soon.

  Runs daily at 08:00 UTC on the `:default` queue. Finds trialing
  subscriptions with `trial_end` within 3 days that have not yet
  been notified, sends a notification via the ecosystem facade,
  and sets `trial_ending_notified = true`.

  Queue: `:default`, max attempts: 1.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  import Ecto.Query

  alias SLE.Ecosystem
  alias SLE.Repo
  alias SLE.Subscriptions.Subscription

  @days_before_trial_end 3

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    find_eligible_subscriptions()
    |> Enum.each(&process_subscription/1)

    :ok
  end

  defp find_eligible_subscriptions do
    cutoff = DateTime.utc_now() |> DateTime.add(@days_before_trial_end, :day)

    Subscription
    |> where([s], s.status == "trialing")
    |> where([s], not is_nil(s.trial_end))
    |> where([s], s.trial_end <= ^cutoff)
    |> where([s], s.trial_ending_notified == false)
    |> join(:inner, [s], c in assoc(s, :customer))
    |> join(:left, [s, _c], p in assoc(s, :plan))
    |> preload([s, c, p], customer: c, plan: p)
    |> Repo.all()
  end

  defp process_subscription(sub) do
    payload = build_payload(sub)

    Ecosystem.emit_notification("subscription.trial_ending", payload)
    mark_notified(sub)

    Logger.info(
      "TrialEndingCheckJob: notified subscription #{sub.id} " <>
        "(trial_end: #{sub.trial_end})"
    )
  end

  defp build_payload(sub) do
    %{
      subscription_id: sub.id,
      tenant_id: sub.tenant_id,
      email: sub.customer.email,
      customer_name: sub.customer.name,
      plan_name: if(sub.plan, do: sub.plan.name, else: nil),
      trial_end: sub.trial_end
    }
  end

  defp mark_notified(sub) do
    sub
    |> Subscription.changeset(%{trial_ending_notified: true})
    |> Repo.update!()
  end
end
