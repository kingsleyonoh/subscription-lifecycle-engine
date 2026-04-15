defmodule SLE.Stripe.Client do
  @moduledoc """
  Stripe API client implementing `SLE.Stripe.ClientBehaviour`.

  Wraps `stripity_stripe` library calls with error handling:
  - Rate limits: respects Retry-After header
  - 402: expected for payment failures (returns structured error)
  - 404: marks as stripe_deleted
  - Timeout: retries once with 2s backoff
  """

  @behaviour SLE.Stripe.ClientBehaviour

  require Logger

  @doc """
  Retry payment for an invoice. POST /v1/invoices/:id/pay
  """
  @impl true
  @spec retry_invoice(String.t()) :: {:ok, map()} | {:error, term()}
  def retry_invoice(stripe_invoice_id) do
    with_retry(fn ->
      case Stripe.Invoice.pay(stripe_invoice_id, %{}) do
        {:ok, invoice} -> {:ok, normalize_invoice(invoice)}
        {:error, error} -> handle_stripe_error(error)
      end
    end)
  end

  @doc """
  Cancel a subscription. POST /v1/subscriptions/:id with cancel options.
  """
  @impl true
  @spec cancel_subscription(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def cancel_subscription(stripe_subscription_id, opts \\ []) do
    cancel_at_period_end = Keyword.get(opts, :cancel_at_period_end, false)

    with_retry(fn ->
      params = %{cancel_at_period_end: cancel_at_period_end}

      case Stripe.Subscription.update(stripe_subscription_id, params) do
        {:ok, sub} -> {:ok, normalize_subscription(sub)}
        {:error, error} -> handle_stripe_error(error)
      end
    end)
  end

  @doc """
  Get an invoice by Stripe ID.
  """
  @impl true
  @spec get_invoice(String.t()) :: {:ok, map()} | {:error, term()}
  def get_invoice(stripe_invoice_id) do
    with_retry(fn ->
      case Stripe.Invoice.retrieve(stripe_invoice_id) do
        {:ok, invoice} -> {:ok, normalize_invoice(invoice)}
        {:error, error} -> handle_stripe_error(error)
      end
    end)
  end

  @doc """
  Get a subscription by Stripe ID.
  """
  @impl true
  @spec get_subscription(String.t()) :: {:ok, map()} | {:error, term()}
  def get_subscription(stripe_subscription_id) do
    with_retry(fn ->
      case Stripe.Subscription.retrieve(stripe_subscription_id) do
        {:ok, sub} -> {:ok, normalize_subscription(sub)}
        {:error, error} -> handle_stripe_error(error)
      end
    end)
  end

  @doc """
  Get a customer by Stripe ID.
  """
  @impl true
  @spec get_customer(String.t()) :: {:ok, map()} | {:error, term()}
  def get_customer(stripe_customer_id) do
    with_retry(fn ->
      case Stripe.Customer.retrieve(stripe_customer_id) do
        {:ok, customer} -> {:ok, normalize_customer(customer)}
        {:error, error} -> handle_stripe_error(error)
      end
    end)
  end

  # --- Private Helpers ---

  defp with_retry(fun) do
    case fun.() do
      {:error, :timeout} ->
        Logger.warning("[SLE.Stripe.Client] Timeout, retrying after 2s backoff")
        Process.sleep(2_000)
        fun.()

      {:error, {:rate_limited, retry_after}} ->
        Logger.warning("[SLE.Stripe.Client] Rate limited, retrying after #{retry_after}s")
        Process.sleep(retry_after * 1_000)
        fun.()

      result ->
        result
    end
  end

  defp handle_stripe_error(%{code: :timeout}), do: {:error, :timeout}
  defp handle_stripe_error(%{message: _, code: :timeout}), do: {:error, :timeout}

  defp handle_stripe_error(%Stripe.Error{} = error) do
    case error.extra do
      %{http_status: 429, raw_error: raw} ->
        retry_after = Map.get(raw || %{}, "retry_after", 1)
        {:error, {:rate_limited, retry_after}}

      %{http_status: 402} ->
        {:error, {:payment_failed, error.message}}

      %{http_status: 404} ->
        {:error, :stripe_not_found}

      _ ->
        Logger.error("[SLE.Stripe.Client] Stripe error: #{inspect(error)}")
        {:error, {:stripe_error, error.message}}
    end
  end

  defp handle_stripe_error(error) do
    Logger.error("[SLE.Stripe.Client] Unknown error: #{inspect(error)}")
    {:error, {:unknown, inspect(error)}}
  end

  defp normalize_invoice(invoice) do
    %{
      id: invoice.id,
      status: invoice.status,
      amount_due: invoice.amount_due,
      amount_paid: invoice.amount_paid,
      currency: invoice.currency,
      customer: invoice.customer,
      subscription: invoice.subscription
    }
  end

  defp normalize_subscription(sub) do
    %{
      id: sub.id,
      status: sub.status,
      cancel_at_period_end: sub.cancel_at_period_end,
      current_period_start: sub.current_period_start,
      current_period_end: sub.current_period_end,
      customer: sub.customer
    }
  end

  defp normalize_customer(customer) do
    %{
      id: customer.id,
      email: customer.email,
      name: customer.name
    }
  end
end
