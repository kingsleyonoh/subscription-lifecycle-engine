defmodule SLE.Jobs.StaleCleanupJob do
  @moduledoc """
  Oban cron worker that prunes stale event payloads.

  Runs daily at 04:00 UTC on the `:default` queue. Sets the
  `payload` column to an empty map for processed subscription
  events older than 90 days, reducing storage usage while
  preserving event metadata.

  Queue: `:default`, max attempts: 1.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  import Ecto.Query

  alias SLE.Repo
  alias SLE.Subscriptions.SubscriptionEvent

  @retention_days 90

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@retention_days, :day)
      |> DateTime.truncate(:second)

    {count, _} =
      SubscriptionEvent
      |> where([e], not is_nil(e.processed_at))
      |> where([e], e.processed_at < ^cutoff)
      |> where([e], e.payload != ^%{})
      |> Repo.update_all(set: [payload: %{}])

    Logger.info("StaleCleanupJob: pruned payload from #{count} events")

    :ok
  end
end
