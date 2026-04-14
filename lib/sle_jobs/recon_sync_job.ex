defmodule SLE.Jobs.ReconSyncJob do
  @moduledoc """
  Oban cron worker that syncs paid invoices to the Recon Engine.

  Runs every 6 hours on the `:ecosystem` queue. Finds all paid
  invoices with `synced_to_recon = false`, transforms them into
  the Recon transaction format, and sends them as a batch via
  `SLE.Ecosystem.sync_transactions/1`.

  On success: marks invoices `synced_to_recon = true`.
  On failure: leaves `synced_to_recon = false` (retry next cycle).

  Queue: `:ecosystem`, max attempts: 3.
  """

  use Oban.Worker, queue: :ecosystem, max_attempts: 3

  require Logger

  import Ecto.Query

  alias SLE.Billing.Invoice
  alias SLE.Customers.Customer
  alias SLE.Ecosystem
  alias SLE.Repo

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{}) do
    invoices = fetch_unsynced_invoices()

    if Enum.empty?(invoices) do
      Logger.info("ReconSyncJob: no unsynced invoices to sync")
      :ok
    else
      sync_batch(invoices)
    end
  end

  defp fetch_unsynced_invoices do
    Invoice
    |> where([i], i.status == "paid" and i.synced_to_recon == false)
    |> preload([], [])
    |> Repo.all()
  end

  defp sync_batch(invoices) do
    transactions = Enum.map(invoices, &build_transaction/1)

    case Ecosystem.sync_transactions(transactions) do
      {:ok, _response} ->
        mark_synced(invoices)
        Logger.info("ReconSyncJob: synced #{length(invoices)} invoices")

      {:error, reason} ->
        Logger.warning("ReconSyncJob: sync failed: #{inspect(reason)}, will retry next cycle")

      :ok ->
        # Feature flag disabled — facade returns :ok
        Logger.info("ReconSyncJob: recon engine disabled, skipping")
    end

    :ok
  end

  defp build_transaction(invoice) do
    customer_email = resolve_customer_email(invoice.customer_id)
    subscription_id = resolve_subscription_stripe_id(invoice.subscription_id)

    %{
      reference: invoice.stripe_invoice_id,
      amount: invoice.amount_paid_cents,
      currency: invoice.currency,
      type: "credit",
      source: "stripe",
      date: format_datetime(invoice.paid_at),
      metadata: %{
        stripe_charge_id: invoice.stripe_charge_id,
        subscription_id: subscription_id,
        customer_email: customer_email
      }
    }
  end

  defp resolve_customer_email(nil), do: nil

  defp resolve_customer_email(customer_id) do
    Customer
    |> where([c], c.id == ^customer_id)
    |> select([c], c.email)
    |> Repo.one()
  end

  defp resolve_subscription_stripe_id(nil), do: nil

  defp resolve_subscription_stripe_id(subscription_id) do
    SLE.Subscriptions.Subscription
    |> where([s], s.id == ^subscription_id)
    |> select([s], s.stripe_subscription_id)
    |> Repo.one()
  end

  defp mark_synced(invoices) do
    ids = Enum.map(invoices, & &1.id)

    Invoice
    |> where([i], i.id in ^ids)
    |> Repo.update_all(set: [synced_to_recon: true])
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
