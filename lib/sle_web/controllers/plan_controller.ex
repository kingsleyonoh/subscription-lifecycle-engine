defmodule SLEWeb.PlanController do
  @moduledoc """
  Handles plan CRUD endpoints.

  ## Endpoints

    * `GET /api/plans` — list plans (tenant-scoped, active by default)
    * `POST /api/plans` — create a local plan mapping
    * `PUT /api/plans/:id` — update plan name/is_active
  """

  use SLEWeb, :controller

  alias SLE.Billing

  action_fallback SLEWeb.FallbackController

  @doc """
  GET /api/plans

  Lists plans for the authenticated tenant. Returns only active plans
  by default. Pass `include_inactive=true` to include all.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    tenant_id = conn.assigns.tenant_id

    opts =
      []
      |> maybe_include_inactive(params)
      |> maybe_paginate(params)

    plans = Billing.list_plans(tenant_id, opts)
    json(conn, %{data: Enum.map(plans, &serialize_plan/1)})
  end

  @doc """
  POST /api/plans

  Creates a new local plan mapping for the authenticated tenant.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    tenant_id = conn.assigns.tenant_id

    attrs = %{
      stripe_price_id: params["stripe_price_id"],
      name: params["name"],
      amount_cents: params["amount_cents"],
      currency: params["currency"] || "usd",
      interval: params["interval"],
      is_active: Map.get(params, "is_active", true),
      metadata: Map.get(params, "metadata", %{})
    }

    case Billing.create_plan(tenant_id, attrs) do
      {:ok, plan} ->
        conn
        |> put_status(:created)
        |> json(serialize_plan(plan))

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  PUT /api/plans/:id

  Updates a plan's name or is_active status.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = params) do
    tenant_id = conn.assigns.tenant_id

    attrs =
      %{}
      |> maybe_put(:name, params["name"])
      |> maybe_put(:is_active, params["is_active"])

    case Billing.update_plan(tenant_id, id, attrs) do
      {:ok, plan} ->
        json(conn, serialize_plan(plan))

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  # --- Private Helpers ---

  defp serialize_plan(plan) do
    %{
      id: plan.id,
      stripe_price_id: plan.stripe_price_id,
      name: plan.name,
      amount_cents: plan.amount_cents,
      currency: plan.currency,
      interval: plan.interval,
      is_active: plan.is_active,
      metadata: plan.metadata,
      inserted_at: plan.inserted_at,
      updated_at: plan.updated_at
    }
  end

  defp maybe_include_inactive(opts, %{"include_inactive" => "true"}),
    do: Keyword.put(opts, :include_inactive, true)

  defp maybe_include_inactive(opts, _), do: opts

  defp maybe_paginate(opts, params) do
    opts
    |> maybe_put_int(:limit, params["limit"])
    |> maybe_put_int(:offset, params["offset"])
  end

  defp maybe_put_int(opts, _key, nil), do: opts

  defp maybe_put_int(opts, key, val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> Keyword.put(opts, key, int)
      :error -> opts
    end
  end

  defp maybe_put_int(opts, key, val) when is_integer(val),
    do: Keyword.put(opts, key, val)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
