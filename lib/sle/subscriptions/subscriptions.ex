defmodule SLE.Subscriptions do
  @moduledoc """
  Context for subscription lifecycle management.

  Handles tenant-scoped CRUD, status transitions via state machine,
  and event listing. Stripe sync logic lives in `SLE.Subscriptions.SubscriptionSync`.
  All operations enforce tenant isolation.
  """

  import Ecto.Query

  alias SLE.Pagination
  alias SLE.Repo
  alias SLE.Subscriptions.{StateMachine, Subscription, SubscriptionEvent, SubscriptionSync}

  @default_limit 25

  # --- Public API ---

  @doc """
  Transition a subscription to a new status via the state machine.

  Validates the transition is allowed before persisting. Returns
  `{:ok, subscription}`, `{:error, :invalid_transition}`, or
  `{:error, :not_found}`.
  """
  @spec transition(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, Subscription.t()} | {:error, :invalid_transition | :not_found}
  def transition(tenant_id, subscription_id, new_status) do
    case get_raw(tenant_id, subscription_id) do
      nil ->
        {:error, :not_found}

      sub ->
        case StateMachine.transition!(sub.status, new_status) do
          :ok ->
            sub
            |> Subscription.changeset(%{status: new_status})
            |> Repo.update()

          {:error, :invalid_transition} ->
            {:error, :invalid_transition}
        end
    end
  end

  @doc """
  List subscriptions scoped by tenant_id.

  Supports filtering by status, customer_id, plan_id and
  offset/limit pagination.
  """
  @spec list(Ecto.UUID.t(), keyword()) :: [Subscription.t()]
  def list(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    Subscription
    |> where([s], s.tenant_id == ^tenant_id)
    |> maybe_filter_status(opts)
    |> maybe_filter_customer(opts)
    |> maybe_filter_plan(opts)
    |> order_by([s], asc: s.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Get a subscription by UUID, scoped to tenant.

  Preloads customer and plan associations.
  Returns `{:ok, subscription}` or `{:error, :not_found}`.
  """
  @spec get(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Subscription.t()} | {:error, :not_found}
  def get(tenant_id, id) do
    Subscription
    |> where([s], s.tenant_id == ^tenant_id and s.id == ^id)
    |> preload([:customer, :plan])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      sub -> {:ok, sub}
    end
  end

  @doc """
  Cancel a subscription.

  Options:
    - `immediate: true` — transitions to canceled immediately
    - `at_period_end: true` — sets cancel_at_period_end flag
  """
  @spec cancel(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, Subscription.t()}
          | {:error, :invalid_transition | :not_found}
  def cancel(tenant_id, id, opts \\ []) do
    case get_raw(tenant_id, id) do
      nil ->
        {:error, :not_found}

      sub ->
        if Keyword.get(opts, :at_period_end, false) do
          sub
          |> Subscription.changeset(%{cancel_at_period_end: true})
          |> Repo.update()
        else
          do_immediate_cancel(sub)
        end
    end
  end

  @doc """
  Pause a subscription. Only allowed from active status.

  Returns `{:error, :conflict}` if subscription is past_due.
  """
  @spec pause(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Subscription.t()}
          | {:error, :conflict | :invalid_transition | :not_found}
  def pause(tenant_id, id) do
    case get_raw(tenant_id, id) do
      nil ->
        {:error, :not_found}

      %{status: "past_due"} ->
        {:error, :conflict}

      sub ->
        case StateMachine.transition!(sub.status, "paused") do
          :ok ->
            sub
            |> Subscription.changeset(%{status: "paused"})
            |> Repo.update()

          {:error, :invalid_transition} ->
            {:error, :invalid_transition}
        end
    end
  end

  @doc """
  Resume a paused subscription. Only from paused status.
  """
  @spec resume(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Subscription.t()}
          | {:error, :not_paused | :not_found}
  def resume(tenant_id, id) do
    case get_raw(tenant_id, id) do
      nil ->
        {:error, :not_found}

      %{status: "paused"} = sub ->
        sub
        |> Subscription.changeset(%{status: "active"})
        |> Repo.update()

      _sub ->
        {:error, :not_paused}
    end
  end

  @doc """
  Create or update a subscription from Stripe webhook event data.

  Delegates to `SLE.Subscriptions.SubscriptionSync.upsert_from_stripe/2`.
  """
  defdelegate upsert_from_stripe(tenant_id, stripe_data), to: SubscriptionSync

  @doc """
  List events for a subscription, scoped to tenant.

  Returns events ordered by id ascending. Supports cursor-based pagination.

  ## Options

    - `:event_type` — filter by event type string
    - `:since` — filter events created after this DateTime
  """
  @spec list_events(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, [SubscriptionEvent.t()], map()} | {:error, :not_found}
  def list_events(tenant_id, subscription_id, opts \\ []) do
    case get_raw(tenant_id, subscription_id) do
      nil ->
        {:error, :not_found}

      _sub ->
        query =
          SubscriptionEvent
          |> where([e], e.tenant_id == ^tenant_id and e.subscription_id == ^subscription_id)
          |> maybe_filter_event_type(opts)
          |> maybe_filter_since(opts)
          |> order_by([e], asc: e.id)

        cursor = Keyword.get(opts, :cursor)
        limit = Keyword.get(opts, :limit, @default_limit)

        {events, meta} = Pagination.paginate(query, cursor: cursor, limit: limit)
        {:ok, events, meta}
    end
  end

  # --- Private Helpers ---

  defp get_raw(tenant_id, id) do
    Subscription
    |> where([s], s.tenant_id == ^tenant_id and s.id == ^id)
    |> Repo.one()
  end

  defp do_immediate_cancel(sub) do
    case StateMachine.transition!(sub.status, "canceled") do
      :ok ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        sub
        |> Subscription.changeset(%{status: "canceled", canceled_at: now})
        |> Repo.update()

      {:error, :invalid_transition} ->
        {:error, :invalid_transition}
    end
  end

  defp maybe_filter_status(query, opts) do
    case Keyword.get(opts, :status) do
      nil -> query
      status -> where(query, [s], s.status == ^status)
    end
  end

  defp maybe_filter_customer(query, opts) do
    case Keyword.get(opts, :customer_id) do
      nil -> query
      customer_id -> where(query, [s], s.customer_id == ^customer_id)
    end
  end

  defp maybe_filter_plan(query, opts) do
    case Keyword.get(opts, :plan_id) do
      nil -> query
      plan_id -> where(query, [s], s.plan_id == ^plan_id)
    end
  end

  defp maybe_filter_event_type(query, opts) do
    case Keyword.get(opts, :event_type) do
      nil -> query
      event_type -> where(query, [e], e.event_type == ^event_type)
    end
  end

  defp maybe_filter_since(query, opts) do
    case Keyword.get(opts, :since) do
      nil ->
        query

      since_str when is_binary(since_str) ->
        case DateTime.from_iso8601(since_str) do
          {:ok, dt, _} -> where(query, [e], e.inserted_at >= ^dt)
          _ -> query
        end

      %DateTime{} = dt ->
        where(query, [e], e.inserted_at >= ^dt)
    end
  end
end
