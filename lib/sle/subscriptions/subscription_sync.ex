defmodule SLE.Subscriptions.SubscriptionSync do
  @moduledoc """
  Stripe sync logic for subscriptions.

  Handles upsert from Stripe webhook data — resolves customer and plan
  references, builds attributes from Stripe payloads, and performs
  insert-or-update. Extracted from `SLE.Subscriptions` for modularity.
  """

  import Ecto.Query

  alias SLE.Billing.Plan
  alias SLE.Customers.Customer
  alias SLE.Repo
  alias SLE.Subscriptions.Subscription

  @doc """
  Create or update a subscription from Stripe webhook event data.

  Looks up the customer by stripe_customer_id within the tenant.
  Optionally resolves plan_id from the first item's price ID.
  """
  @spec upsert_from_stripe(Ecto.UUID.t(), map()) ::
          {:ok, Subscription.t()}
          | {:error, :customer_not_found | Ecto.Changeset.t()}
  def upsert_from_stripe(tenant_id, stripe_data) do
    stripe_sub_id = Map.get(stripe_data, "id")
    stripe_customer_id = Map.get(stripe_data, "customer")

    case resolve_customer(tenant_id, stripe_customer_id) do
      nil ->
        {:error, :customer_not_found}

      customer ->
        plan_id = resolve_plan_id(tenant_id, stripe_data)
        attrs = build_attrs_from_stripe(tenant_id, customer.id, plan_id, stripe_data)

        case get_by_stripe_id(tenant_id, stripe_sub_id) do
          nil ->
            %Subscription{}
            |> Subscription.changeset(attrs)
            |> Repo.insert()

          existing ->
            existing
            |> Subscription.changeset(attrs)
            |> Repo.update()
        end
    end
  end

  # --- Private Helpers ---

  defp get_by_stripe_id(_tenant_id, nil), do: nil

  defp get_by_stripe_id(tenant_id, stripe_sub_id) do
    Subscription
    |> where([s], s.tenant_id == ^tenant_id and s.stripe_subscription_id == ^stripe_sub_id)
    |> Repo.one()
  end

  defp resolve_customer(_tenant_id, nil), do: nil

  defp resolve_customer(tenant_id, stripe_customer_id) do
    Customer
    |> where([c], c.tenant_id == ^tenant_id and c.stripe_customer_id == ^stripe_customer_id)
    |> Repo.one()
  end

  defp resolve_plan_id(tenant_id, stripe_data) do
    items = get_in(stripe_data, ["items", "data"]) || []

    case items do
      [first | _] ->
        price_id = get_in(first, ["price", "id"])

        if price_id do
          Plan
          |> where([p], p.tenant_id == ^tenant_id and p.stripe_price_id == ^price_id)
          |> select([p], p.id)
          |> Repo.one()
        end

      _ ->
        nil
    end
  end

  defp build_attrs_from_stripe(tenant_id, customer_id, plan_id, data) do
    %{
      tenant_id: tenant_id,
      customer_id: customer_id,
      plan_id: plan_id,
      stripe_subscription_id: Map.get(data, "id"),
      status: Map.get(data, "status"),
      current_period_start: parse_timestamp(Map.get(data, "current_period_start")),
      current_period_end: parse_timestamp(Map.get(data, "current_period_end")),
      trial_start: parse_timestamp(Map.get(data, "trial_start")),
      trial_end: parse_timestamp(Map.get(data, "trial_end")),
      canceled_at: parse_timestamp(Map.get(data, "canceled_at")),
      ended_at: parse_timestamp(Map.get(data, "ended_at")),
      cancel_at_period_end: Map.get(data, "cancel_at_period_end", false),
      metadata: Map.get(data, "metadata", %{})
    }
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(ts) when is_integer(ts) do
    DateTime.from_unix!(ts) |> DateTime.truncate(:second)
  end

  defp parse_timestamp(%DateTime{} = dt), do: dt
end
