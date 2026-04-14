defmodule SLE.Webhooks.Processors.InvoiceProcessor do
  @moduledoc """
  Processes `invoice.*` webhook events.

  Handles: invoice.created, invoice.updated, invoice.paid,
  invoice.payment_failed, invoice.voided, invoice.finalized.

  Upserts invoice from event data and links to subscription
  when `data.object.subscription` is present.
  """

  require Logger

  alias SLE.Billing
  alias SLE.Subscriptions.SubscriptionEvent

  @doc """
  Process an invoice-related webhook event.

  Returns `{:ok, invoice}` on success, or `{:ok, :skipped}` when
  the payload is missing required data.
  """
  @spec process(SubscriptionEvent.t()) :: {:ok, map() | :skipped} | {:error, term()}
  def process(%SubscriptionEvent{} = event) do
    tenant_id = event.tenant_id
    stripe_data = get_in(event.payload, ["data", "object"]) || %{}
    stripe_inv_id = Map.get(stripe_data, "id")

    if is_nil(stripe_inv_id) do
      Logger.warning("InvoiceProcessor: missing invoice ID in payload, skipping")
      {:ok, :skipped}
    else
      upsert_invoice(tenant_id, stripe_data, stripe_inv_id, event)
    end
  end

  defp upsert_invoice(tenant_id, stripe_data, stripe_inv_id, event) do
    case Billing.upsert_invoice(tenant_id, stripe_data) do
      {:ok, invoice} ->
        Logger.info(
          "InvoiceProcessor: #{event.event_type} processed invoice #{invoice.stripe_invoice_id}"
        )

        {:ok, invoice}

      {:error, changeset} ->
        Logger.error(
          "InvoiceProcessor: failed to upsert invoice #{stripe_inv_id}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end
end
