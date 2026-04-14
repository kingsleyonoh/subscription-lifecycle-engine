defmodule SLE.Ecosystem.NotificationHubBehaviour do
  @moduledoc """
  Behaviour for Notification Hub client.
  """

  @callback send_event(String.t(), map()) ::
              :ok | {:error, term()}
end
