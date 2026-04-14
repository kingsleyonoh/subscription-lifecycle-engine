defmodule SLE.Factory do
  @moduledoc """
  ExMachina factory for test data.

  Factories are added here as schemas are implemented.
  """

  use ExMachina.Ecto, repo: SLE.Repo

  alias SLE.Billing.{Invoice, Plan}
  alias SLE.Customers.Customer
  alias SLE.Subscriptions.Subscription
  alias SLE.Tenants.Tenant

  def tenant_factory do
    api_key = "sle_live_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
    hash = :crypto.hash(:sha256, api_key) |> Base.encode16(case: :lower)

    %Tenant{
      name: sequence(:tenant_name, &"Test Tenant #{&1}"),
      api_key_hash: hash,
      api_key_prefix: String.slice(api_key, 0, 13),
      stripe_config: %{},
      is_active: true
    }
  end

  def customer_factory do
    %Customer{
      stripe_customer_id: sequence(:stripe_customer_id, &"cus_test_#{&1}"),
      email: sequence(:customer_email, &"customer#{&1}@example.com"),
      name: sequence(:customer_name, &"Customer #{&1}"),
      metadata: %{}
    }
  end

  def plan_factory do
    %Plan{
      stripe_price_id: sequence(:stripe_price_id, &"price_test_#{&1}"),
      name: sequence(:plan_name, &"Plan #{&1}"),
      amount_cents: 1999,
      currency: "usd",
      interval: "month",
      is_active: true,
      metadata: %{}
    }
  end

  def subscription_factory do
    %Subscription{
      stripe_subscription_id: sequence(:stripe_subscription_id, &"sub_test_#{&1}"),
      status: "active",
      current_period_start: DateTime.utc_now() |> DateTime.truncate(:second),
      current_period_end:
        DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second),
      cancel_at_period_end: false,
      trial_ending_notified: false,
      metadata: %{}
    }
  end

  def invoice_factory do
    %Invoice{
      stripe_invoice_id: sequence(:stripe_invoice_id, &"in_test_#{&1}"),
      status: "open",
      amount_due_cents: 2999,
      amount_paid_cents: 0,
      currency: "usd",
      attempt_count: 0,
      synced_to_recon: false,
      metadata: %{}
    }
  end
end
