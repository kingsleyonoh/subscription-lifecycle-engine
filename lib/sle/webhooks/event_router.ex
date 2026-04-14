defmodule SLE.Webhooks.EventRouter do
  @moduledoc """
  Routes webhook events to the appropriate processor module based
  on the event_type prefix.

  ## Routing rules

    * `"customer.subscription.*"` -> SubscriptionProcessor
    * `"invoice.*"` -> InvoiceProcessor
    * `"payment_intent.*"` -> PaymentProcessor
    * Unknown -> `:unknown` (mark processed, no further processing)
  """

  require Logger

  alias SLE.Subscriptions.SubscriptionEvent
  alias SLE.Webhooks.Processors.{InvoiceProcessor, PaymentProcessor, SubscriptionProcessor}

  @doc """
  Route a subscription event to the correct processor.

  Returns `{:ok, processor_name}` indicating which processor was
  selected (or `:unknown` for unrecognized event types).
  """
  @spec route(SubscriptionEvent.t()) ::
          {:ok, :subscription_processor | :invoice_processor | :payment_processor | :unknown}
  def route(%SubscriptionEvent{event_type: "customer.subscription." <> _} = event) do
    SubscriptionProcessor.process(event)
    {:ok, :subscription_processor}
  end

  def route(%SubscriptionEvent{event_type: "invoice." <> _} = event) do
    InvoiceProcessor.process(event)
    {:ok, :invoice_processor}
  end

  def route(%SubscriptionEvent{event_type: "payment_intent." <> _} = event) do
    PaymentProcessor.process(event)
    {:ok, :payment_processor}
  end

  def route(%SubscriptionEvent{event_type: event_type}) do
    Logger.warning("Unknown event type: #{event_type} — skipping processing")
    {:ok, :unknown}
  end
end
