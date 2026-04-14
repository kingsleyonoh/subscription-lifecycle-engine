defmodule SLEWeb.HealthController do
  @moduledoc """
  Health check endpoints for monitoring and readiness probes.

  ## Endpoints

    * `GET /api/health` — system health (database + Oban)
    * `GET /api/health/db` — database latency check
    * `GET /api/health/ready` — combined readiness (Traefik probe)
  """

  use SLEWeb, :controller

  alias SLE.Repo

  @db_timeout 2_000
  @degraded_threshold_ms 1_000

  @doc """
  GET /api/health

  Returns system health: database connectivity and Oban status.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    db_status = check_database()
    oban_status = check_oban()

    overall =
      if db_status == "connected" do
        "ok"
      else
        "error"
      end

    status_code = if overall == "ok", do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: overall,
      database: db_status,
      oban: oban_status
    })
  end

  @doc """
  GET /api/health/db

  Returns database latency via `SELECT 1`.
  Status is "ok" if < 1000ms, "degraded" if >= 1000ms, "error" on failure.
  """
  @spec db(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def db(conn, _params) do
    {status, latency_ms} = measure_db_latency()

    status_code = if status == "error", do: 503, else: 200

    conn
    |> put_status(status_code)
    |> json(%{
      status: status,
      latencyMs: latency_ms
    })
  end

  @doc """
  GET /api/health/ready

  Combined readiness probe for Traefik. Includes database, Oban, and latency.
  """
  @spec ready(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ready(conn, _params) do
    db_status = check_database()
    oban_status = check_oban()
    {_db_health, latency_ms} = measure_db_latency()

    overall =
      if db_status == "connected" do
        "ok"
      else
        "error"
      end

    status_code = if overall == "ok", do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: overall,
      database: db_status,
      oban: oban_status,
      latencyMs: latency_ms
    })
  end

  # --- Private ---

  defp check_database do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: @db_timeout) do
      {:ok, _} -> "connected"
      {:error, _} -> "disconnected"
    end
  rescue
    _ -> "disconnected"
  end

  defp check_oban do
    # In test mode with testing: :inline, Oban doesn't run as a process
    case Process.whereis(Oban) do
      nil ->
        # Check if Oban is configured for inline testing
        case Application.get_env(:sle, Oban) do
          config when is_list(config) ->
            if Keyword.get(config, :testing) == :inline, do: "inline", else: "stopped"

          _ ->
            "stopped"
        end

      pid when is_pid(pid) ->
        if Process.alive?(pid), do: "running", else: "stopped"
    end
  end

  defp measure_db_latency do
    start = System.monotonic_time(:microsecond)

    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: @db_timeout) do
      {:ok, _} ->
        elapsed_us = System.monotonic_time(:microsecond) - start
        latency_ms = elapsed_us / 1_000.0

        status =
          if latency_ms >= @degraded_threshold_ms do
            "degraded"
          else
            "ok"
          end

        {status, Float.round(latency_ms, 2)}

      {:error, _} ->
        {"error", 0.0}
    end
  rescue
    _ -> {"error", 0.0}
  end
end
