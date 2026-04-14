defmodule SLE.Webhooks.Processors.InvoiceProcessor do
  @moduledoc """
  Processes `invoice.*` webhook events.

  Stub implementation — real processing (upsert invoice, update
  subscription period) will be added in a future batch.
  """

  require Logger

  alias SLE.Subscriptions.SubscriptionEvent

  @doc """
  Process an invoice-related event. Currently a stub that logs
  and returns `:ok`.
  """
  @spec process(SubscriptionEvent.t()) :: :ok
  def process(%SubscriptionEvent{event_type: event_type, id: id}) do
    Logger.info("InvoiceProcessor stub: #{event_type} (event #{id})")
    :ok
  end
end
