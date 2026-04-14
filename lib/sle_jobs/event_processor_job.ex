defmodule SLE.Jobs.EventProcessorJob do
  @moduledoc """
  Oban worker that processes a single subscription event.

  Loads the event by ID, routes it to the appropriate processor
  via `EventRouter`, and marks it as processed on success or
  records the error on failure.

  Queue: `:webhooks`, max attempts: 5.
  """

  use Oban.Worker, queue: :webhooks, max_attempts: 5

  require Logger

  alias SLE.Repo
  alias SLE.Subscriptions.SubscriptionEvent
  alias SLE.Webhooks.EventRouter

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"subscription_event_id" => event_id}}) do
    case Repo.get(SubscriptionEvent, event_id) do
      nil ->
        Logger.error("EventProcessorJob: event #{event_id} not found")
        {:error, :event_not_found}

      %SubscriptionEvent{processed_at: %DateTime{}} ->
        Logger.info("EventProcessorJob: event #{event_id} already processed")
        :ok

      event ->
        process_event(event)
    end
  end

  defp process_event(event) do
    {:ok, _processor} = EventRouter.route(event)
    mark_processed(event)
    :ok
  rescue
    e ->
      mark_error(event, Exception.message(e))
      reraise e, __STACKTRACE__
  end

  defp mark_processed(event) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    event
    |> SubscriptionEvent.changeset(%{processed_at: now})
    |> Repo.update!()
  end

  defp mark_error(event, error_message) do
    event
    |> SubscriptionEvent.changeset(%{processing_error: error_message})
    |> Repo.update()
  end
end
