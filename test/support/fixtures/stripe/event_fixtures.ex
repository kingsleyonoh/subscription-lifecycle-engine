defmodule SLE.Fixtures.StripeEvents do
  @moduledoc """
  Generates realistic Stripe webhook event payloads for testing.

  Each function returns a map matching Stripe's event JSON structure.
  """

  @doc "Builds a customer.subscription.created event payload."
  @spec subscription_created(keyword()) :: map()
  def subscription_created(opts \\ []) do
    stripe_sub_id = Keyword.get(opts, :stripe_sub_id, "sub_test_123")
    stripe_customer_id = Keyword.get(opts, :stripe_customer_id, "cus_test_456")
    stripe_price_id = Keyword.get(opts, :stripe_price_id, "price_test_789")
    status = Keyword.get(opts, :status, "trialing")

    %{
      "id" => Keyword.get(opts, :event_id, "evt_sub_created_1"),
      "type" => "customer.subscription.created",
      "data" => %{
        "object" =>
          subscription_object(
            stripe_sub_id,
            stripe_customer_id,
            stripe_price_id,
            status,
            opts
          ),
        "previous_attributes" => Keyword.get(opts, :previous_attributes, %{})
      }
    }
  end

  @doc "Builds a customer.subscription.updated event payload."
  @spec subscription_updated(keyword()) :: map()
  def subscription_updated(opts \\ []) do
    stripe_sub_id = Keyword.get(opts, :stripe_sub_id, "sub_test_123")
    stripe_customer_id = Keyword.get(opts, :stripe_customer_id, "cus_test_456")
    stripe_price_id = Keyword.get(opts, :stripe_price_id, "price_test_789")
    status = Keyword.get(opts, :status, "active")

    %{
      "id" => Keyword.get(opts, :event_id, "evt_sub_updated_1"),
      "type" => "customer.subscription.updated",
      "data" => %{
        "object" =>
          subscription_object(
            stripe_sub_id,
            stripe_customer_id,
            stripe_price_id,
            status,
            opts
          ),
        "previous_attributes" => Keyword.get(opts, :previous_attributes, %{})
      }
    }
  end

  @doc "Builds a customer.subscription.deleted event payload."
  @spec subscription_deleted(keyword()) :: map()
  def subscription_deleted(opts \\ []) do
    stripe_sub_id = Keyword.get(opts, :stripe_sub_id, "sub_test_123")
    stripe_customer_id = Keyword.get(opts, :stripe_customer_id, "cus_test_456")
    stripe_price_id = Keyword.get(opts, :stripe_price_id, "price_test_789")

    %{
      "id" => Keyword.get(opts, :event_id, "evt_sub_deleted_1"),
      "type" => "customer.subscription.deleted",
      "data" => %{
        "object" =>
          subscription_object(
            stripe_sub_id,
            stripe_customer_id,
            stripe_price_id,
            "canceled",
            opts
          ),
        "previous_attributes" => Keyword.get(opts, :previous_attributes, %{})
      }
    }
  end

  @doc "Builds an invoice event payload for the given event type."
  @spec invoice_event(String.t(), keyword()) :: map()
  def invoice_event(event_type, opts \\ []) do
    %{
      "id" => Keyword.get(opts, :event_id, "evt_inv_1"),
      "type" => event_type,
      "data" => %{
        "object" => invoice_object(opts),
        "previous_attributes" => Keyword.get(opts, :previous_attributes, %{})
      }
    }
  end

  @doc "Builds a payment_intent event payload."
  @spec payment_intent_event(String.t(), keyword()) :: map()
  def payment_intent_event(event_type, opts \\ []) do
    %{
      "id" => Keyword.get(opts, :event_id, "evt_pi_1"),
      "type" => event_type,
      "data" => %{
        "object" => payment_intent_object(opts),
        "previous_attributes" => Keyword.get(opts, :previous_attributes, %{})
      }
    }
  end

  # --- Private Builders ---

  defp subscription_object(sub_id, cus_id, price_id, status, opts) do
    now = System.system_time(:second)

    base = %{
      "id" => sub_id,
      "customer" => cus_id,
      "status" => status,
      "items" => %{
        "data" => build_items(price_id, opts)
      },
      "current_period_start" => Keyword.get(opts, :period_start, now),
      "current_period_end" => Keyword.get(opts, :period_end, now + 30 * 86_400),
      "trial_start" => Keyword.get(opts, :trial_start, nil),
      "trial_end" => Keyword.get(opts, :trial_end, nil),
      "cancel_at_period_end" => Keyword.get(opts, :cancel_at_period_end, false),
      "canceled_at" => Keyword.get(opts, :canceled_at, nil),
      "ended_at" => Keyword.get(opts, :ended_at, nil),
      "metadata" => Keyword.get(opts, :metadata, %{})
    }

    if Keyword.get(opts, :trial_start) do
      Map.merge(base, %{
        "trial_start" => Keyword.get(opts, :trial_start),
        "trial_end" => Keyword.get(opts, :trial_end)
      })
    else
      base
    end
  end

  defp build_items(price_id, opts) do
    amount = Keyword.get(opts, :amount_cents, 2999)
    currency = Keyword.get(opts, :currency, "usd")
    interval = Keyword.get(opts, :interval, "month")

    items = [
      %{
        "price" => %{
          "id" => price_id,
          "unit_amount" => amount,
          "currency" => currency,
          "recurring" => %{"interval" => interval},
          "product" => Keyword.get(opts, :product_id, "prod_test_1")
        }
      }
    ]

    extra = Keyword.get(opts, :extra_items, [])
    items ++ extra
  end

  defp invoice_object(opts) do
    now = System.system_time(:second)
    status = Keyword.get(opts, :status, "open")

    %{
      "id" => Keyword.get(opts, :stripe_invoice_id, "in_test_123"),
      "customer" => Keyword.get(opts, :stripe_customer_id, "cus_test_456"),
      "subscription" => Keyword.get(opts, :stripe_subscription_id, nil),
      "status" => status,
      "amount_due" => Keyword.get(opts, :amount_due, 2999),
      "amount_paid" => Keyword.get(opts, :amount_paid, 0),
      "currency" => Keyword.get(opts, :currency, "usd"),
      "charge" => Keyword.get(opts, :charge_id, nil),
      "period_start" => Keyword.get(opts, :period_start, now),
      "period_end" => Keyword.get(opts, :period_end, now + 30 * 86_400),
      "due_date" => Keyword.get(opts, :due_date, nil),
      "paid_at" => Keyword.get(opts, :paid_at, nil),
      "attempt_count" => Keyword.get(opts, :attempt_count, 0),
      "next_payment_attempt" => Keyword.get(opts, :next_payment_attempt, nil),
      "hosted_invoice_url" => Keyword.get(opts, :hosted_invoice_url, nil),
      "metadata" => Keyword.get(opts, :metadata, %{})
    }
  end

  defp payment_intent_object(opts) do
    %{
      "id" => Keyword.get(opts, :stripe_payment_intent_id, "pi_test_123"),
      "invoice" => Keyword.get(opts, :stripe_invoice_id, nil),
      "status" => Keyword.get(opts, :status, "succeeded"),
      "amount" => Keyword.get(opts, :amount, 2999),
      "currency" => Keyword.get(opts, :currency, "usd"),
      "charges" => %{
        "data" => [
          %{"id" => Keyword.get(opts, :charge_id, "ch_test_123")}
        ]
      },
      "metadata" => Keyword.get(opts, :metadata, %{})
    }
  end
end
