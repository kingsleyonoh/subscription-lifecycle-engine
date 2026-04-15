defmodule SLE.Ecosystem.ClientPortalBehaviour do
  @moduledoc """
  Behaviour for Client Management Portal client.
  """

  @callback push_metrics(map()) ::
              :ok | {:error, term()}
end
