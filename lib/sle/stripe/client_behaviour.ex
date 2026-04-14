defmodule SLE.Stripe.ClientBehaviour do
  @moduledoc """
  Behaviour for Stripe API client.

  Defines the contract for Stripe operations used by the SLE.
  Mocked in tests to avoid real Stripe API calls.
  """

  @callback retry_invoice(String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback cancel_subscription(String.t(), keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback get_subscription(String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback get_invoice(String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback get_customer(String.t()) ::
              {:ok, map()} | {:error, term()}
end
