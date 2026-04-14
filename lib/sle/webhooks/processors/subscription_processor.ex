defmodule SLE.Webhooks.Processors.SubscriptionProcessor do
  @moduledoc """
  Processes `customer.subscription.*` webhook events.

  Flow for each event:
    1. Upsert customer from `data.object.customer`
    2. Upsert plan from first item's price
    3. Check state machine transition validity
    4. Upsert subscription (skip status if transition is invalid)
    5. Record previous_status and new_status on the event
  """

  require Logger

  import Ecto.Query

  alias SLE.Billing
  alias SLE.Customers
  alias SLE.Repo
  alias SLE.Subscriptions
  alias SLE.Subscriptions.{StateMachine, Subscription, SubscriptionEvent}

  @doc """
  Process a subscription-related webhook event.

  Returns `{:ok, subscription}` on success.
  """
  @spec process(SubscriptionEvent.t()) :: {:ok, map()} | {:error, term()}
  def process(%SubscriptionEvent{} = event) do
    tenant_id = event.tenant_id
    stripe_data = get_in(event.payload, ["data", "object"]) || %{}

    with {:ok, _customer} <- upsert_customer(tenant_id, stripe_data),
         {:ok, _plan} <- upsert_plan(tenant_id, stripe_data),
         {:ok, subscription} <- upsert_subscription(tenant_id, stripe_data, event) do
      {:ok, subscription}
    end
  end

  # --- Private Helpers ---

  defp upsert_customer(_tenant_id, %{"customer" => nil}), do: {:ok, nil}
  defp upsert_customer(_tenant_id, data) when not is_map_key(data, "customer"), do: {:ok, nil}

  defp upsert_customer(tenant_id, stripe_data) do
    stripe_customer_id = Map.get(stripe_data, "customer")

    customer_data = %{
      "id" => stripe_customer_id,
      "email" => nil,
      "name" => nil,
      "metadata" => %{}
    }

    Customers.upsert_from_stripe(tenant_id, customer_data)
  end

  defp upsert_plan(tenant_id, stripe_data) do
    items = get_in(stripe_data, ["items", "data"]) || []
    warn_multiple_items(items)

    case items do
      [first | _] -> upsert_plan_from_item(tenant_id, first)
      [] -> {:ok, nil}
    end
  end

  defp upsert_plan_from_item(tenant_id, item) do
    price = Map.get(item, "price", %{})

    attrs = %{
      stripe_price_id: Map.get(price, "id"),
      name: Map.get(price, "product", "Unknown Plan"),
      amount_cents: Map.get(price, "unit_amount", 0),
      currency: Map.get(price, "currency", "usd"),
      interval: get_in(price, ["recurring", "interval"]) || "month"
    }

    Billing.upsert_plan(tenant_id, attrs)
  end

  defp upsert_subscription(_tenant_id, %{"id" => nil}, _event) do
    Logger.warning("SubscriptionProcessor: missing subscription ID in payload, skipping")
    {:ok, :skipped}
  end

  defp upsert_subscription(_tenant_id, data, _event) when not is_map_key(data, "id") do
    Logger.warning("SubscriptionProcessor: missing subscription ID in payload, skipping")
    {:ok, :skipped}
  end

  defp upsert_subscription(tenant_id, stripe_data, event) do
    stripe_sub_id = Map.get(stripe_data, "id")
    new_status = Map.get(stripe_data, "status")
    existing = find_existing(tenant_id, stripe_sub_id)
    previous_status = resolve_previous_status(event, existing)

    data_for_upsert = maybe_strip_status(stripe_data, previous_status, new_status)

    case Subscriptions.upsert_from_stripe(tenant_id, data_for_upsert) do
      {:ok, subscription} ->
        actual_new = subscription.status
        update_event_statuses(event, subscription, previous_status, actual_new)
        {:ok, subscription}

      {:error, reason} ->
        Logger.error(
          "SubscriptionProcessor: failed to upsert sub #{stripe_sub_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp find_existing(_tenant_id, nil), do: nil

  defp find_existing(tenant_id, stripe_sub_id) do
    Subscription
    |> where([s], s.tenant_id == ^tenant_id and s.stripe_subscription_id == ^stripe_sub_id)
    |> Repo.one()
  end

  defp resolve_previous_status(event, existing) do
    prev_from_event =
      get_in(event.payload, ["data", "previous_attributes", "status"])

    cond do
      prev_from_event != nil -> prev_from_event
      existing != nil -> existing.status
      true -> nil
    end
  end

  defp maybe_strip_status(stripe_data, nil, _new_status), do: stripe_data
  defp maybe_strip_status(stripe_data, prev, new) when prev == new, do: stripe_data

  defp maybe_strip_status(stripe_data, previous_status, new_status) do
    case StateMachine.transition!(previous_status, new_status) do
      :ok ->
        stripe_data

      {:error, :invalid_transition} ->
        Logger.warning(
          "SubscriptionProcessor: invalid transition #{previous_status} -> #{new_status}, " <>
            "keeping current status"
        )

        Map.put(stripe_data, "status", previous_status)
    end
  end

  defp update_event_statuses(event, subscription, previous_status, new_status) do
    event
    |> SubscriptionEvent.changeset(%{
      subscription_id: subscription.id,
      previous_status: previous_status,
      new_status: new_status
    })
    |> Repo.update()
  end

  defp warn_multiple_items(items) when length(items) > 1 do
    Logger.warning(
      "SubscriptionProcessor: subscription has #{length(items)} items, using first price only"
    )
  end

  defp warn_multiple_items(_), do: :ok
end
