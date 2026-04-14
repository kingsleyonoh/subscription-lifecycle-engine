defmodule SLE.E2E.HealthE2ETest do
  @moduledoc """
  E2E tests for health endpoints hitting a running HTTP server.

  These tests verify the full request lifecycle including server startup,
  middleware chain, and JSON serialization.
  """

  use ExUnit.Case, async: false

  setup_all do
    # Allow any process to check out DB connections (E2E requests
    # come from Bandit handler processes, not the test process)
    Ecto.Adapters.SQL.Sandbox.mode(SLE.Repo, :auto)

    {:ok, server} =
      Bandit.start_link(
        plug: SLEWeb.Endpoint,
        port: 0,
        ip: {127, 0, 0, 1},
        scheme: :http
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    base_url = "http://127.0.0.1:#{port}"

    await_ready(base_url, 20)

    on_exit(fn ->
      GenServer.stop(server)
      Ecto.Adapters.SQL.Sandbox.mode(SLE.Repo, :manual)
    end)

    %{base_url: base_url}
  end

  describe "GET /api/health" do
    test "returns 200 with system health", %{base_url: base_url} do
      {:ok, resp} = Req.get("#{base_url}/api/health", retry: false)

      assert resp.status == 200
      assert resp.body["status"] == "ok"
      assert resp.body["database"] == "connected"
      assert resp.body["oban"] in ["running", "inline"]
    end
  end

  describe "GET /api/health/db" do
    test "returns 200 with database latency", %{base_url: base_url} do
      {:ok, resp} = Req.get("#{base_url}/api/health/db", retry: false)

      assert resp.status == 200
      assert resp.body["status"] in ["ok", "degraded"]
      assert is_number(resp.body["latencyMs"])
      assert resp.body["latencyMs"] >= 0
    end
  end

  describe "GET /api/health/ready" do
    test "returns 200 with readiness status", %{base_url: base_url} do
      {:ok, resp} = Req.get("#{base_url}/api/health/ready", retry: false)

      assert resp.status == 200
      assert resp.body["status"] == "ok"
      assert resp.body["database"] == "connected"
      assert is_number(resp.body["latencyMs"])
    end
  end

  defp await_ready(_base_url, 0), do: flunk("E2E server failed to start")

  defp await_ready(base_url, retries) do
    case Req.get("#{base_url}/api/health", retry: false) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      _ ->
        Process.sleep(250)
        await_ready(base_url, retries - 1)
    end
  rescue
    _ ->
      Process.sleep(250)
      await_ready(base_url, retries - 1)
  end
end
