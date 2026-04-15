defmodule SLE.E2E.SubscriptionActionsE2ETest do
  @moduledoc """
  E2E tests for subscription action endpoints (cancel/pause/resume)
  hitting a running HTTP server.
  """

  use ExUnit.Case, async: false

  import SLE.Factory

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

  setup %{base_url: url} do
    # Register a tenant via the API
    {:ok, reg} =
      Req.post("#{url}/api/tenants/register",
        json: %{"name" => "E2E Sub Actions Test"},
        retry: false
      )

    api_key = reg.body["apiKey"]
    tenant_id = reg.body["id"]

    # Insert test data directly
    customer = insert(:customer, tenant_id: tenant_id)

    %{api_key: api_key, tenant_id: tenant_id, customer: customer}
  end

  describe "POST /api/subscriptions/:id/cancel" do
    test "cancels subscription at period end via real HTTP", %{
      base_url: url,
      api_key: api_key,
      tenant_id: tenant_id,
      customer: customer
    } do
      sub =
        insert(:subscription,
          tenant_id: tenant_id,
          customer_id: customer.id,
          status: "active"
        )

      {:ok, resp} =
        Req.post("#{url}/api/subscriptions/#{sub.id}/cancel",
          json: %{"at_period_end" => true},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert resp.body["subscription"]["cancel_at_period_end"] == true
    end

    test "immediate cancel via real HTTP", %{
      base_url: url,
      api_key: api_key,
      tenant_id: tenant_id,
      customer: customer
    } do
      sub =
        insert(:subscription,
          tenant_id: tenant_id,
          customer_id: customer.id,
          status: "active"
        )

      {:ok, resp} =
        Req.post("#{url}/api/subscriptions/#{sub.id}/cancel",
          json: %{"at_period_end" => false},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert resp.body["subscription"]["status"] == "canceled"
    end

    test "returns 401 without auth", %{base_url: url} do
      {:ok, resp} =
        Req.post("#{url}/api/subscriptions/#{Ecto.UUID.generate()}/cancel",
          json: %{"at_period_end" => true},
          retry: false
        )

      assert resp.status == 401
    end
  end

  describe "POST /api/subscriptions/:id/pause" do
    test "pauses active subscription via real HTTP", %{
      base_url: url,
      api_key: api_key,
      tenant_id: tenant_id,
      customer: customer
    } do
      sub =
        insert(:subscription,
          tenant_id: tenant_id,
          customer_id: customer.id,
          status: "active"
        )

      {:ok, resp} =
        Req.post("#{url}/api/subscriptions/#{sub.id}/pause",
          json: %{},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert resp.body["subscription"]["status"] == "paused"
    end

    test "returns 409 for past_due subscription", %{
      base_url: url,
      api_key: api_key,
      tenant_id: tenant_id,
      customer: customer
    } do
      sub =
        insert(:subscription,
          tenant_id: tenant_id,
          customer_id: customer.id,
          status: "past_due"
        )

      {:ok, resp} =
        Req.post("#{url}/api/subscriptions/#{sub.id}/pause",
          json: %{},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 409
    end
  end

  describe "POST /api/subscriptions/:id/resume" do
    test "resumes paused subscription via real HTTP", %{
      base_url: url,
      api_key: api_key,
      tenant_id: tenant_id,
      customer: customer
    } do
      sub =
        insert(:subscription,
          tenant_id: tenant_id,
          customer_id: customer.id,
          status: "paused"
        )

      {:ok, resp} =
        Req.post("#{url}/api/subscriptions/#{sub.id}/resume",
          json: %{},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert resp.body["subscription"]["status"] == "active"
    end

    test "returns 409 for non-paused subscription", %{
      base_url: url,
      api_key: api_key,
      tenant_id: tenant_id,
      customer: customer
    } do
      sub =
        insert(:subscription,
          tenant_id: tenant_id,
          customer_id: customer.id,
          status: "active"
        )

      {:ok, resp} =
        Req.post("#{url}/api/subscriptions/#{sub.id}/resume",
          json: %{},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 409
    end
  end

  defp await_ready(_base_url, 0), do: flunk("E2E server failed to start")

  defp await_ready(base_url, retries) do
    case Req.get("#{base_url}/api/health", retry: false) do
      {:ok, %{status: s}} when s in 200..299 ->
        :ok

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
