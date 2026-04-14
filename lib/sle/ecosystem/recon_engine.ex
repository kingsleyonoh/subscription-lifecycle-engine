defmodule SLE.Ecosystem.ReconEngine do
  @moduledoc """
  HTTP client for the Transaction Reconciliation Engine.

  Implements `SLE.Ecosystem.ReconEngineBehaviour`.

  Posts a batch of transactions for reconciliation.
  Returns `{:ok, response_body}` or `{:error, reason}`.
  Graceful degradation: if offline, logs and returns error
  (caller marks synced_to_recon = false).
  """

  @behaviour SLE.Ecosystem.ReconEngineBehaviour

  require Logger

  @timeout 10_000

  @impl true
  @spec sync_transactions(list(map())) :: {:ok, map()} | {:error, term()}
  def sync_transactions(transactions) do
    url = Application.get_env(:sle, :recon_engine_url)
    api_key = Application.get_env(:sle, :recon_engine_api_key)

    body = Jason.encode!(%{transactions: transactions})

    case Req.post("#{url}/api/v1/transactions/ingest/batch",
           body: body,
           headers: [
             {"content-type", "application/json"},
             {"x-api-key", api_key}
           ],
           receive_timeout: @timeout,
           connect_options: [timeout: @timeout],
           retry: false
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        parsed =
          case resp_body do
            %{} = map -> map
            body when is_binary(body) -> Jason.decode!(body)
          end

        Logger.info("ReconEngine: synced #{length(transactions)} transactions")
        {:ok, parsed}

      {:ok, %{status: status}} ->
        Logger.warning("ReconEngine: batch ingest returned #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("ReconEngine: batch ingest failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
