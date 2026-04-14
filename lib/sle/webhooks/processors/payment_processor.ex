defmodule SLE.Webhooks.Processors.PaymentProcessor do
  @moduledoc """
  Processes `payment_intent.*` webhook events.

  Stub implementation — real processing (update invoice payment
  status) will be added in a future batch.
  """

  require Logger

  alias SLE.Subscriptions.SubscriptionEvent

  @doc """
  Process a payment-intent-related event. Currently a stub that
  logs and returns `:ok`.
  """
  @spec process(SubscriptionEvent.t()) :: :ok
  def process(%SubscriptionEvent{event_type: event_type, id: id}) do
    Logger.info("PaymentProcessor stub: #{event_type} (event #{id})")
    :ok
  end
end
