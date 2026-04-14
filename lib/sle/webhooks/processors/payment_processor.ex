defmodule SLE.Webhooks.Processors.PaymentProcessor do
  @moduledoc """
  Processes `payment_intent.*` webhook events.

  Handles: payment_intent.succeeded, payment_intent.payment_failed.

  Matches to an existing invoice via `data.object.invoice` and
  updates the invoice's stripe_charge_id.
  """

  require Logger

  import Ecto.Query

  alias SLE.Billing.Invoice
  alias SLE.Repo
  alias SLE.Subscriptions.SubscriptionEvent

  @doc """
  Process a payment-intent-related webhook event.

  Returns `{:ok, :updated}` when invoice was found and updated,
  or `{:ok, :no_invoice}` when no matching invoice exists.
  """
  @spec process(SubscriptionEvent.t()) :: {:ok, :updated | :no_invoice} | {:error, term()}
  def process(%SubscriptionEvent{} = event) do
    tenant_id = event.tenant_id
    stripe_data = get_in(event.payload, ["data", "object"]) || %{}
    stripe_invoice_id = Map.get(stripe_data, "invoice")
    charge_id = extract_charge_id(stripe_data)

    case find_invoice(tenant_id, stripe_invoice_id) do
      nil ->
        Logger.info(
          "PaymentProcessor: no invoice found for payment_intent " <>
            "(invoice_id: #{inspect(stripe_invoice_id)})"
        )

        {:ok, :no_invoice}

      invoice ->
        update_invoice_charge(invoice, charge_id, event.event_type)
    end
  end

  # --- Private Helpers ---

  defp find_invoice(_tenant_id, nil), do: nil

  defp find_invoice(tenant_id, stripe_invoice_id) do
    Invoice
    |> where([i], i.tenant_id == ^tenant_id and i.stripe_invoice_id == ^stripe_invoice_id)
    |> Repo.one()
  end

  defp extract_charge_id(stripe_data) do
    case get_in(stripe_data, ["charges", "data"]) do
      [%{"id" => charge_id} | _] -> charge_id
      _ -> nil
    end
  end

  defp update_invoice_charge(invoice, charge_id, event_type) do
    attrs = %{stripe_charge_id: charge_id}

    case invoice
         |> Invoice.changeset(attrs)
         |> Repo.update() do
      {:ok, updated} ->
        Logger.info(
          "PaymentProcessor: #{event_type} updated invoice #{updated.stripe_invoice_id}"
        )

        {:ok, :updated}

      {:error, changeset} ->
        Logger.error(
          "PaymentProcessor: failed to update invoice #{invoice.stripe_invoice_id}: " <>
            inspect(changeset)
        )

        {:error, changeset}
    end
  end
end
