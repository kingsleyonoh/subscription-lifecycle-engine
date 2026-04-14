defmodule SLE.E2E.TenantE2ETest do
  @moduledoc """
  E2E tests for tenant endpoints hitting a running HTTP server.

  Tests the full lifecycle: registration, authentication, and profile.
  """

  use ExUnit.Case, async: false

  setup_all do
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

  describe "POST /api/tenants/register" do
    test "creates tenant and returns API key", %{base_url: url} do
      {:ok, resp} =
        Req.post("#{url}/api/tenants/register",
          json: %{"name" => "E2E Test SaaS"},
          retry: false
        )

      assert resp.status == 201
      assert resp.body["name"] == "E2E Test SaaS"
      assert is_binary(resp.body["id"])
      assert String.starts_with?(resp.body["apiKey"], "sle_live_")
    end

    test "returns 400 for missing name", %{base_url: url} do
      {:ok, resp} =
        Req.post("#{url}/api/tenants/register",
          json: %{},
          retry: false
        )

      assert resp.status == 400
      assert resp.body["error"]["code"] == "VALIDATION_ERROR"
    end
  end

  describe "GET /api/tenants/me" do
    test "full lifecycle: register then profile", %{base_url: url} do
      {:ok, reg} =
        Req.post("#{url}/api/tenants/register",
          json: %{"name" => "E2E Profile Test"},
          retry: false
        )

      api_key = reg.body["apiKey"]
      tenant_id = reg.body["id"]

      {:ok, resp} =
        Req.get("#{url}/api/tenants/me",
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert resp.body["id"] == tenant_id
      assert resp.body["name"] == "E2E Profile Test"
      assert is_binary(resp.body["apiKeyPrefix"])
      assert resp.body["isActive"] == true
      assert is_binary(resp.body["createdAt"])
    end

    test "returns 401 without API key", %{base_url: url} do
      {:ok, resp} = Req.get("#{url}/api/tenants/me", retry: false)

      assert resp.status == 401
      assert resp.body["error"]["code"] == "UNAUTHORIZED"
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
