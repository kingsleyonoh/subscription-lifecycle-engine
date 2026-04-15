defmodule SLEWeb.DunningController do
  @moduledoc """
  Handles dunning endpoints.

  ## Endpoints

    * `GET /api/dunning` — list active dunning attempts (tenant-scoped, cursor pagination)
    * `GET /api/dunning/:id` — detail with full error_log
  """

  use SLEWeb, :controller

  alias SLE.Dunning

  action_fallback SLEWeb.FallbackController

  @doc "GET /api/dunning — list with cursor pagination and filters."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    tenant_id = conn.assigns.tenant_id
    limit = parse_int(params["limit"], 25)
    cursor = params["cursor"]

    opts =
      [limit: limit]
      |> maybe_put_opt(:cursor, cursor)
      |> maybe_put_opt(:status, params["status"])
      |> maybe_put_opt(:subscription_id, params["subscription_id"])

    result = Dunning.list(tenant_id, opts)

    json(conn, %{
      data: Enum.map(result.data, &serialize_dunning/1),
      meta: %{cursor: result.meta.cursor, hasMore: result.meta.has_more}
    })
  end

  @doc "GET /api/dunning/:id — detail with full error_log."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    tenant_id = conn.assigns.tenant_id

    with {:ok, dunning} <- Dunning.get(tenant_id, id) do
      json(conn, %{dunning: serialize_dunning_detail(dunning)})
    end
  end

  # --- Serializers ---

  defp serialize_dunning(d) do
    %{
      id: d.id,
      status: d.status,
      attemptNumber: d.attempt_number,
      maxAttempts: d.max_attempts,
      escalationChannel: d.escalation_channel,
      subscriptionId: d.subscription_id,
      invoiceId: d.invoice_id,
      customerId: d.customer_id,
      lastAttemptedAt: format_dt(d.last_attempted_at),
      nextAttemptAt: format_dt(d.next_attempt_at),
      recoveryAmount: d.recovery_amount,
      insertedAt: format_dt(d.inserted_at),
      updatedAt: format_dt(d.updated_at)
    }
  end

  defp serialize_dunning_detail(d) do
    d
    |> serialize_dunning()
    |> Map.put(:errorLog, d.error_log)
    |> Map.put(:notificationPayload, d.notification_payload)
  end

  # --- Helpers ---

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, val), do: Keyword.put(opts, key, val)

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
