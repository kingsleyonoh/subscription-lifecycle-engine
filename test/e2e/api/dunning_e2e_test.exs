defmodule SLE.E2E.DunningE2ETest do
  @moduledoc """
  E2E tests for dunning endpoints hitting a running HTTP server.
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
    {:ok, reg} =
      Req.post("#{url}/api/tenants/register",
        json: %{"name" => "E2E Dunning Test"},
        retry: false
      )

    api_key = reg.body["apiKey"]
    tenant_id = reg.body["id"]

    customer = insert(:customer, tenant_id: tenant_id)

    sub =
      insert(:subscription,
        tenant_id: tenant_id,
        customer_id: customer.id,
        status: "past_due"
      )

    %{api_key: api_key, tenant_id: tenant_id, customer: customer, subscription: sub}
  end

  describe "GET /api/dunning" do
    test "returns empty list when no dunning attempts", %{
      base_url: url,
      api_key: api_key
    } do
      {:ok, resp} =
        Req.get("#{url}/api/dunning",
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert resp.body["data"] == []
      assert resp.body["meta"]["hasMore"] == false
    end

    test "returns dunning attempts for tenant", %{
      base_url: url,
      api_key: api_key,
      tenant_id: tenant_id,
      customer: customer,
      subscription: sub
    } do
      inv =
        insert(:invoice,
          tenant_id: tenant_id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      insert(:dunning_attempt,
        tenant_id: tenant_id,
        subscription_id: sub.id,
        invoice_id: inv.id,
        customer_id: customer.id,
        status: "retrying",
        attempt_number: 1,
        notification_payload: %{"template" => "test"}
      )

      {:ok, resp} =
        Req.get("#{url}/api/dunning",
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert length(resp.body["data"]) == 1
      assert hd(resp.body["data"])["status"] == "retrying"
    end

    test "returns 401 without auth", %{base_url: url} do
      {:ok, resp} = Req.get("#{url}/api/dunning", retry: false)
      assert resp.status == 401
    end
  end

  describe "GET /api/dunning/:id" do
    test "returns dunning detail with error_log", %{
      base_url: url,
      api_key: api_key,
      tenant_id: tenant_id,
      customer: customer,
      subscription: sub
    } do
      inv =
        insert(:invoice,
          tenant_id: tenant_id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      da =
        insert(:dunning_attempt,
          tenant_id: tenant_id,
          subscription_id: sub.id,
          invoice_id: inv.id,
          customer_id: customer.id,
          status: "retrying",
          attempt_number: 2,
          error_log: [%{"message" => "Card declined"}],
          notification_payload: %{"template" => "test"}
        )

      {:ok, resp} =
        Req.get("#{url}/api/dunning/#{da.id}",
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert resp.body["dunning"]["id"] == da.id
      assert resp.body["dunning"]["status"] == "retrying"
      assert length(resp.body["dunning"]["errorLog"]) == 1
    end

    test "returns 404 for non-existent dunning", %{base_url: url, api_key: api_key} do
      {:ok, resp} =
        Req.get("#{url}/api/dunning/#{Ecto.UUID.generate()}",
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 404
    end

    test "returns 401 without auth", %{base_url: url} do
      {:ok, resp} =
        Req.get("#{url}/api/dunning/#{Ecto.UUID.generate()}", retry: false)

      assert resp.status == 401
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
