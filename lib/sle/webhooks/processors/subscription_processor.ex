defmodule SLE.Webhooks.Processors.SubscriptionProcessor do
  @moduledoc """
  Processes `customer.subscription.*` webhook events.

  Stub implementation — real processing (upsert customer, plan,
  subscription via state machine) will be added in a future batch.
  """

  require Logger

  alias SLE.Subscriptions.SubscriptionEvent

  @doc """
  Process a subscription-related event. Currently a stub that logs
  and returns `:ok`.
  """
  @spec process(SubscriptionEvent.t()) :: :ok
  def process(%SubscriptionEvent{event_type: event_type, id: id}) do
    Logger.info("SubscriptionProcessor stub: #{event_type} (event #{id})")
    :ok
  end
end
