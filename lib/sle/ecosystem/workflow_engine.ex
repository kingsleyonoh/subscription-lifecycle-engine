defmodule SLE.Ecosystem.WorkflowEngine do
  @moduledoc """
  HTTP client for the Workflow Automation Engine.

  Implements `SLE.Ecosystem.WorkflowEngineBehaviour`.

  Posts trigger data to execute a specific workflow by ID.
  Returns `{:ok, execution_id}` or `{:error, reason}`.
  """

  @behaviour SLE.Ecosystem.WorkflowEngineBehaviour

  require Logger

  @timeout 10_000

  @impl true
  @spec execute_workflow(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def execute_workflow(workflow_id, trigger_data) do
    url = Application.get_env(:sle, :workflow_engine_url)
    api_key = Application.get_env(:sle, :workflow_engine_api_key)

    body = Jason.encode!(%{trigger_data: trigger_data})

    case Req.post("#{url}/api/workflows/#{workflow_id}/execute",
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
        execution_id =
          case resp_body do
            %{"execution_id" => id} -> id
            body when is_binary(body) -> Jason.decode!(body) |> Map.get("execution_id")
            _ -> nil
          end

        Logger.info("WorkflowEngine: executed #{workflow_id} -> #{execution_id}")
        {:ok, execution_id}

      {:ok, %{status: status}} ->
        Logger.warning("WorkflowEngine: #{workflow_id} returned #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("WorkflowEngine: #{workflow_id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
