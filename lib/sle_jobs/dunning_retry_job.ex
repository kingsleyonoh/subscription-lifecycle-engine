defmodule SLE.Jobs.DunningRetryJob do
  @moduledoc """
  Oban worker that retries payment for a dunning attempt.

  Flow:
    1. Load dunning attempt with subscription + invoice preloaded
    2. Check invoice status via Stripe API
    3. If already paid -> recover dunning
    4. If unpaid -> retry invoice payment
    5. If retry succeeds -> recover dunning, transition subscription to active
    6. If retry fails -> advance dunning (increment attempt, log error)
    7. If max attempts reached -> exhaust dunning

  Queue: `:dunning`, max attempts: 3.
  """

  use Oban.Worker, queue: :dunning, max_attempts: 3

  require Logger

  alias SLE.Dunning
  alias SLE.Subscriptions

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"dunning_attempt_id" => dunning_id, "tenant_id" => tenant_id}}) do
    case Dunning.get(tenant_id, dunning_id) do
      {:error, :not_found} ->
        Logger.error("DunningRetryJob: dunning attempt #{dunning_id} not found")
        {:error, :dunning_not_found}

      {:ok, dunning} ->
        process_retry(dunning, tenant_id)
    end
  end

  # --- Private Helpers ---

  defp process_retry(dunning, tenant_id) do
    stripe_invoice_id = dunning.invoice.stripe_invoice_id

    case stripe_client().get_invoice(stripe_invoice_id) do
      {:ok, %{status: "paid"} = invoice_data} ->
        handle_already_paid(dunning, tenant_id, invoice_data)

      {:ok, _invoice_data} ->
        attempt_retry(dunning, tenant_id, stripe_invoice_id)

      {:error, reason} ->
        Logger.error("DunningRetryJob: Stripe get_invoice failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_already_paid(dunning, tenant_id, invoice_data) do
    amount = Map.get(invoice_data, :amount_paid, 0)
    Dunning.recover(tenant_id, dunning.id, amount)
    :ok
  end

  defp attempt_retry(dunning, tenant_id, stripe_invoice_id) do
    case stripe_client().retry_invoice(stripe_invoice_id) do
      {:ok, %{status: "paid"} = invoice_data} ->
        handle_retry_success(dunning, tenant_id, invoice_data)

      {:ok, _other} ->
        handle_retry_failure(dunning, tenant_id, "Invoice status not paid after retry")

      {:error, reason} ->
        handle_retry_failure(dunning, tenant_id, inspect(reason))
    end
  end

  defp handle_retry_success(dunning, tenant_id, invoice_data) do
    amount = Map.get(invoice_data, :amount_paid, 0)
    Dunning.recover(tenant_id, dunning.id, amount)
    Subscriptions.transition(tenant_id, dunning.subscription_id, "active")
    :ok
  end

  defp handle_retry_failure(dunning, tenant_id, error_reason) do
    new_attempt = dunning.attempt_number + 1

    if new_attempt >= dunning.max_attempts do
      Dunning.advance(tenant_id, dunning.id, %{"error" => error_reason})
      Dunning.exhaust(tenant_id, dunning.id)
    else
      Dunning.advance(tenant_id, dunning.id, %{"error" => error_reason})
      schedule_next_retry(dunning.id, tenant_id)
    end

    :ok
  end

  defp schedule_next_retry(dunning_id, tenant_id) do
    %{"dunning_attempt_id" => dunning_id, "tenant_id" => tenant_id}
    |> SLE.Jobs.DunningRetryJob.new()
    |> Oban.insert()
  end

  defp stripe_client do
    Application.get_env(:sle, :stripe_client)
  end
end
