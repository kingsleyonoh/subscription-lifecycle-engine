defmodule SLE.Stripe.ClientTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias SLE.Stripe.Client

  setup_all do
    Code.ensure_loaded!(Client)
    :ok
  end

  describe "retry_invoice/1" do
    test "function exists with arity 1" do
      assert function_exported?(Client, :retry_invoice, 1)
    end
  end

  describe "cancel_subscription/2" do
    test "function exists with arity 2" do
      assert function_exported?(Client, :cancel_subscription, 2)
    end
  end

  describe "get_invoice/1" do
    test "function exists with arity 1" do
      assert function_exported?(Client, :get_invoice, 1)
    end
  end

  describe "get_subscription/1" do
    test "function exists with arity 1" do
      assert function_exported?(Client, :get_subscription, 1)
    end
  end

  describe "get_customer/1" do
    test "function exists with arity 1" do
      assert function_exported?(Client, :get_customer, 1)
    end
  end

  describe "behaviour implementation" do
    test "implements SLE.Stripe.ClientBehaviour" do
      behaviours =
        Client.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert SLE.Stripe.ClientBehaviour in behaviours
    end
  end
end
