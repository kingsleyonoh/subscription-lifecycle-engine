defmodule SLEWeb.Plugs.RateLimit do
  @moduledoc """
  Plug that enforces per-{tenant, endpoint} rate limiting using an
  ETS-based sliding window counter.

  For unauthenticated endpoints (no `current_tenant` in assigns),
  rate limiting is applied per {remote_ip, endpoint} instead.

  ## Options

    * `:limit` — max requests per window (default: 100)
    * `:window_ms` — window size in milliseconds (default: 60_000)

  ## PRD Rate Limits (Section 8b)

    * Registration: 5/min (global by IP)
    * Read endpoints: 100/min (per tenant)
    * Write endpoints: 20/min (per tenant)
    * Webhooks: 500/min (per tenant)
  """

  import Plug.Conn

  @behaviour Plug

  @table :sle_rate_limit
  @default_limit 100
  @default_window_ms 60_000

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts) do
    [
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms)
    ]
  end

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    ensure_table()
    key = build_key(conn)
    limit = opts[:limit]
    window_ms = opts[:window_ms]
    now = System.monotonic_time(:millisecond)

    case check_rate(key, limit, window_ms, now) do
      :ok -> conn
      :rate_limited -> reject(conn)
    end
  end

  @doc """
  Clears all rate limit counters. Used in tests.
  """
  @spec reset_all() :: :ok
  def reset_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # --- Private ---

  defp build_key(conn) do
    identity =
      case conn.assigns do
        %{current_tenant: %{id: tenant_id}} -> {:tenant, tenant_id}
        _ -> {:ip, format_ip(conn.remote_ip)}
      end

    {identity, conn.request_path}
  end

  defp format_ip(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()
  defp format_ip(ip), do: to_string(ip)

  defp check_rate(key, limit, window_ms, now) do
    window_start = now - window_ms

    # Clean expired entries and count current window
    case :ets.lookup(@table, key) do
      [{^key, timestamps}] ->
        valid = Enum.filter(timestamps, fn ts -> ts > window_start end)

        if length(valid) >= limit do
          :rate_limited
        else
          :ets.insert(@table, {key, [now | valid]})
          :ok
        end

      [] ->
        :ets.insert(@table, {key, [now]})
        :ok
    end
  end

  defp reject(conn) do
    body =
      Jason.encode!(%{
        error: %{
          code: "RATE_LIMITED",
          message: "Too many requests"
        }
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(429, body)
    |> halt()
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])
    end
  rescue
    ArgumentError -> :ok
  end
end
