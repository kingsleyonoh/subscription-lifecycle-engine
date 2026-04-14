defmodule SLE.Webhooks.Idempotency do
  @moduledoc """
  Idempotency checker for webhook event processing.

  Queries subscription_events for a matching (tenant_id, idempotency_key)
  to determine whether an event has been seen before.

  ## Return values

    * `{:ok, :new}` — event not seen before
    * `{:ok, :duplicate, event}` — already processed (processed_at set)
    * `{:ok, :processing, event}` — in progress (processed_at is nil)
  """

  import Ecto.Query

  alias SLE.Repo
  alias SLE.Subscriptions.SubscriptionEvent

  @doc """
  Check whether a Stripe event has already been received for this tenant.

  Builds the idempotency key as `"tenant_id:stripe_event_id"` and looks
  up the subscription_events table.
  """
  @spec check(Ecto.UUID.t(), String.t()) ::
          {:ok, :new}
          | {:ok, :duplicate, SubscriptionEvent.t()}
          | {:ok, :processing, SubscriptionEvent.t()}
  def check(tenant_id, stripe_event_id) do
    key = build_key(tenant_id, stripe_event_id)

    SubscriptionEvent
    |> where([e], e.tenant_id == ^tenant_id and e.idempotency_key == ^key)
    |> Repo.one()
    |> case do
      nil ->
        {:ok, :new}

      %{processed_at: nil} = event ->
        {:ok, :processing, event}

      event ->
        {:ok, :duplicate, event}
    end
  end

  @doc """
  Build the idempotency key from tenant_id and stripe_event_id.
  """
  @spec build_key(Ecto.UUID.t(), String.t()) :: String.t()
  def build_key(tenant_id, stripe_event_id) do
    "#{tenant_id}:#{stripe_event_id}"
  end
end
