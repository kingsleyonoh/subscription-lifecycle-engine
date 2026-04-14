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
  alias SLE.Repo
  alias SLE.Subscriptions

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    exhausted_attempts =
      DunningAttempt
      |> where([d], d.status == "exhausted")
      |> preload([:subscription])
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
end
