defmodule SLE.Ecosystem do
  @moduledoc """
  Facade for outbound ecosystem integrations.

  All other modules call these facade functions — never import
  client modules directly. Each function checks a feature flag
  and delegates to the configured client module when enabled.
  When disabled, the event is logged and `:ok` is returned.
  """

  require Logger

  # --- Notification Hub ---

  @doc """
  Emit a notification event to the Notification Hub.

  When `notification_hub_enabled` is `false`, logs and returns `:ok`.
  When enabled, delegates to the configured client module.
  Fire-and-forget: always returns `:ok`.
  """
  @spec emit_notification(String.t(), map()) :: :ok
  def emit_notification(event_type, payload) do
    if Application.get_env(:sle, :notification_hub_enabled, false) do
      client = Application.get_env(:sle, :notification_hub_client)
      client.send_event(event_type, payload)
    else
      Logger.info("Ecosystem: notification_hub disabled, skipping #{event_type}")
      :ok
    end
  end

  # --- Workflow Engine ---

  @doc """
  Trigger a workflow execution on the Workflow Engine.

  When `workflow_engine_enabled` is `false`, logs and returns `:ok`.
  When enabled, delegates to the configured client module.
  """
  @spec trigger_workflow(String.t(), map()) :: {:ok, String.t()} | {:error, term()} | :ok
  def trigger_workflow(workflow_id, trigger_data) do
    if Application.get_env(:sle, :workflow_engine_enabled, false) do
      client = Application.get_env(:sle, :workflow_engine_client)
      client.execute_workflow(workflow_id, trigger_data)
    else
      Logger.info("Ecosystem: workflow_engine disabled, skipping workflow #{workflow_id}")
      :ok
    end
  end

  # --- Recon Engine ---

  @doc """
  Sync transactions to the Transaction Reconciliation Engine.

  When `recon_engine_enabled` is `false`, logs and returns `:ok`.
  When enabled, delegates to the configured client module.
  """
  @spec sync_transactions(list(map())) :: {:ok, map()} | {:error, term()} | :ok
  def sync_transactions(transactions) do
    if Application.get_env(:sle, :recon_engine_enabled, false) do
      client = Application.get_env(:sle, :recon_engine_client)
      client.sync_transactions(transactions)
    else
      Logger.info(
        "Ecosystem: recon_engine disabled, skipping #{length(transactions)} transactions"
      )

      :ok
    end
  end

  # --- Client Portal ---

  @doc """
  Push metrics to the Client Management Portal.

  When `client_portal_enabled` is `false`, logs and returns `:ok`.
  When enabled, delegates to the configured client module.
  """
  @spec push_metrics(map()) :: :ok | {:error, term()}
  def push_metrics(metrics) do
    if Application.get_env(:sle, :client_portal_enabled, false) do
      client = Application.get_env(:sle, :client_portal_client)
      client.push_metrics(metrics)
    else
      Logger.info("Ecosystem: client_portal disabled, skipping metrics push")
      :ok
    end
  end
end
