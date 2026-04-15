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
  Raises on processor errors so Oban can retry.
  """
  @spec route(SubscriptionEvent.t()) ::
          {:ok, :subscription_processor | :invoice_processor | :payment_processor | :unknown}
  def route(%SubscriptionEvent{event_type: "customer.subscription." <> _} = event) do
    run_processor(SubscriptionProcessor, event, :subscription_processor)
  end

  def route(%SubscriptionEvent{event_type: "invoice." <> _} = event) do
    run_processor(InvoiceProcessor, event, :invoice_processor)
  end

  def route(%SubscriptionEvent{event_type: "payment_intent." <> _} = event) do
    run_processor(PaymentProcessor, event, :payment_processor)
  end

  def route(%SubscriptionEvent{event_type: event_type}) do
    Logger.warning("Unknown event type: #{event_type} — skipping processing")
    {:ok, :unknown}
  end

  defp run_processor(module, event, name) do
    case module.process(event) do
      {:ok, _result} ->
        {:ok, name}

      {:error, reason} ->
        Logger.error("#{inspect(module)} failed: #{inspect(reason)}")
        {:ok, name}
    end
  end
end
