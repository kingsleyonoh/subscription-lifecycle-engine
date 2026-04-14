defmodule SLE.Ecosystem.WorkflowEngineBehaviour do
  @moduledoc """
  Behaviour for Workflow Automation Engine client.
  """

  @callback execute_workflow(String.t(), map()) ::
              {:ok, String.t()} | {:error, term()}
end
