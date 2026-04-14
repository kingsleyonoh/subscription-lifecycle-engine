defmodule SLEWeb.WebhookController do
  @moduledoc """
  Handles incoming webhook events from the Webhook Ingestion Engine.

  ## Endpoint

    * `POST /api/webhook-handler` — receive Stripe event, check
      idempotency, insert event record, enqueue processor job.

  ## Flow

  1. Extract `id` and `type` from JSON body
  2. Check idempotency (tenant_id + stripe_event_id)
  3. If duplicate (processed) -> return 200 with status "duplicate"
  4. If processing (in progress) -> return 200 with status "processing"
  5. If new -> insert subscription_event, enqueue EventProcessorJob
  6. Return 200 with `{ "received": true }`
  """

  use SLEWeb, :controller

  alias SLE.Jobs.EventProcessorJob
  alias SLE.Repo
  alias SLE.Subscriptions.SubscriptionEvent
  alias SLE.Webhooks.Idempotency

  action_fallback SLEWeb.FallbackController

  @doc """
  POST /api/webhook-handler

  Receives a webhook event and processes it through the idempotency
  and event pipeline.
  """
  @spec handle(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handle(conn, params) do
    tenant_id = conn.assigns.tenant_id
    stripe_event_id = Map.get(params, "id")
    event_type = Map.get(params, "type")

    with :ok <- validate_required_fields(stripe_event_id, event_type),
         {:ok, result} <- process_event(tenant_id, stripe_event_id, event_type, params) do
      json(conn, result)
    end
  end

  defp validate_required_fields(nil, _), do: {:error, :bad_request}
  defp validate_required_fields(_, nil), do: {:error, :bad_request}
  defp validate_required_fields(_, _), do: :ok

  defp process_event(tenant_id, stripe_event_id, event_type, params) do
    case Idempotency.check(tenant_id, stripe_event_id) do
      {:ok, :duplicate, _event} ->
        {:ok, %{received: true, status: "duplicate"}}

      {:ok, :processing, _event} ->
        {:ok, %{received: true, status: "processing"}}

      {:ok, :new} ->
        insert_and_enqueue(tenant_id, stripe_event_id, event_type, params)
    end
  end

  defp insert_and_enqueue(tenant_id, stripe_event_id, event_type, params) do
    idempotency_key = Idempotency.build_key(tenant_id, stripe_event_id)

    attrs = %{
      tenant_id: tenant_id,
      stripe_event_id: stripe_event_id,
      event_type: event_type,
      payload: params,
      idempotency_key: idempotency_key
    }

    case insert_event(attrs) do
      {:ok, event} ->
        enqueue_processor(event)
        {:ok, %{received: true}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp insert_event(attrs) do
    %SubscriptionEvent{}
    |> SubscriptionEvent.changeset(attrs)
    |> Repo.insert()
  end

  defp enqueue_processor(event) do
    %{subscription_event_id: event.id}
    |> EventProcessorJob.new()
    |> Oban.insert()
  end
end
