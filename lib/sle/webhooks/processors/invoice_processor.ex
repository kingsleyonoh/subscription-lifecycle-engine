defmodule SLE.Webhooks.Processors.InvoiceProcessor do
  @moduledoc """
  Processes `invoice.*` webhook events.

  Handles: invoice.created, invoice.updated, invoice.paid,
  invoice.payment_failed, invoice.voided, invoice.finalized.

  Upserts invoice from event data and links to subscription
  when `data.object.subscription` is present.
  """

  require Logger

  import Ecto.Query

  alias SLE.Billing
  alias SLE.Dunning
  alias SLE.Dunning.DunningAttempt
  alias SLE.Repo
  alias SLE.Subscriptions
  alias SLE.Subscriptions.{Subscription, SubscriptionEvent}

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

        if invoice.status == "paid" do
          maybe_recover_dunning(tenant_id, invoice)
        end

        {:ok, invoice}

      {:error, changeset} ->
        Logger.error(
          "InvoiceProcessor: failed to upsert invoice #{stripe_inv_id}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end

  defp maybe_recover_dunning(tenant_id, invoice) do
    with sub when not is_nil(sub) <- find_past_due_subscription(tenant_id, invoice),
         dunning when not is_nil(dunning) <- find_active_dunning(tenant_id, invoice.id) do
      amount = invoice.amount_paid_cents || invoice.amount_due_cents || 0
      Dunning.recover(tenant_id, dunning.id, amount)
      Subscriptions.transition(tenant_id, sub.id, "active")

      Logger.info(
        "InvoiceProcessor: recovered dunning #{dunning.id} for invoice #{invoice.id}"
      )
    end
  end

  defp find_past_due_subscription(tenant_id, invoice) do
    case invoice.subscription_id do
      nil -> nil
      sub_id ->
        Subscription
        |> where([s], s.tenant_id == ^tenant_id and s.id == ^sub_id and s.status == "past_due")
        |> Repo.one()
    end
  end

  defp find_active_dunning(tenant_id, invoice_id) do
    DunningAttempt
    |> where([d], d.tenant_id == ^tenant_id and d.invoice_id == ^invoice_id)
    |> where([d], d.status not in ["recovered", "canceled"])
    |> Repo.one()
  end
end
