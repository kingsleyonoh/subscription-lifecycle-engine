defmodule SLE.Factory do
  @moduledoc """
  ExMachina factory for test data.

  Factories are added here as schemas are implemented.
  """

  use ExMachina.Ecto, repo: SLE.Repo

  alias SLE.Billing.Plan
  alias SLE.Customers.Customer
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
end
