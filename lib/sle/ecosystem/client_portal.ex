defmodule SLE.Ecosystem.ClientPortal do
  @moduledoc """
  HTTP client for the Client Management Portal.

  Implements `SLE.Ecosystem.ClientPortalBehaviour`.

  Pushes metrics data to the portal for display.
  Returns `:ok` or `{:error, reason}`.
  """

  @behaviour SLE.Ecosystem.ClientPortalBehaviour

  require Logger

  @timeout 10_000

  @impl true
  @spec push_metrics(map()) :: :ok | {:error, term()}
  def push_metrics(metrics) do
    url = Application.get_env(:sle, :client_portal_url)
    api_key = Application.get_env(:sle, :client_portal_api_key)

    body = Jason.encode!(metrics)

    case Req.post("#{url}/api/integration/metrics",
           body: body,
           headers: [
             {"content-type", "application/json"},
             {"x-api-key", api_key}
           ],
           receive_timeout: @timeout,
           connect_options: [timeout: @timeout],
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("ClientPortal: pushed metrics successfully")
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("ClientPortal: metrics push returned #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("ClientPortal: metrics push failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
