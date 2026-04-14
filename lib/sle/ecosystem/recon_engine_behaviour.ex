defmodule SLE.Ecosystem.ReconEngineBehaviour do
  @moduledoc """
  Behaviour for Transaction Reconciliation Engine client.
  """

  @callback sync_transactions(list(map())) ::
              {:ok, map()} | {:error, term()}
end
