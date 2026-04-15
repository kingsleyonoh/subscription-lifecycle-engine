defmodule SLEWeb.HealthControllerTest do
  @moduledoc """
  Tests for health check endpoints:
  - GET /api/health (system health)
  - GET /api/health/db (database latency)
  """

  use SLEWeb.ConnCase, async: true

  describe "GET /api/health" do
    test "returns ok with database and oban status", %{conn: conn} do
      conn = get(conn, "/api/health")

      assert %{
               "status" => "ok",
               "database" => "connected",
               "oban" => oban_status
             } = json_response(conn, 200)

      assert oban_status in ["running", "inline"]
    end

    test "does not require authentication", %{conn: conn} do
      # No X-API-Key header needed
      conn = get(conn, "/api/health")
      assert conn.status == 200
    end
  end

  describe "GET /api/health/db" do
    test "returns ok status with latency measurement", %{conn: conn} do
      conn = get(conn, "/api/health/db")

      assert %{
               "status" => status,
               "latencyMs" => latency
             } = json_response(conn, 200)

      assert status in ["ok", "degraded"]
      assert is_number(latency)
      assert latency >= 0
    end

    test "returns latency as a float", %{conn: conn} do
      conn = get(conn, "/api/health/db")

      %{"latencyMs" => latency} = json_response(conn, 200)
      assert is_float(latency) or is_integer(latency)
    end

    test "does not require authentication", %{conn: conn} do
      conn = get(conn, "/api/health/db")
      assert conn.status == 200
    end
  end

  describe "GET /api/health/ready" do
    test "returns combined readiness status", %{conn: conn} do
      conn = get(conn, "/api/health/ready")

      assert %{
               "status" => "ok",
               "database" => "connected",
               "oban" => _oban_status,
               "latencyMs" => latency
             } = json_response(conn, 200)

      assert is_number(latency)
    end

    test "does not require authentication", %{conn: conn} do
      conn = get(conn, "/api/health/ready")
      assert conn.status == 200
    end
  end
end
