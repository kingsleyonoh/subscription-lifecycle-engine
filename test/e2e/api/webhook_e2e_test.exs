defmodule SLE.E2E.WebhookE2ETest do
  @moduledoc """
  E2E tests for webhook handler endpoint hitting a running HTTP server.

  Tests the full webhook reception flow: authentication, idempotency,
  event insertion, and job processing.
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

  setup %{base_url: url} do
    # Register a tenant for auth
    {:ok, reg} =
      Req.post("#{url}/api/tenants/register",
        json: %{"name" => "E2E Webhook Test"},
        retry: false
      )

    api_key = reg.body["apiKey"]
    tenant_id = reg.body["id"]

    %{api_key: api_key, tenant_id: tenant_id}
  end

  describe "POST /api/webhook-handler" do
    test "accepts a new webhook event", %{base_url: url, api_key: api_key} do
      payload = %{
        "id" => "evt_e2e_#{System.unique_integer([:positive])}",
        "type" => "customer.subscription.created",
        "data" => %{"object" => %{"id" => "sub_e2e", "status" => "trialing"}}
      }

      {:ok, resp} =
        Req.post("#{url}/api/webhook-handler",
          json: payload,
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 200
      assert resp.body["received"] == true
    end

    test "returns duplicate for already-processed event", %{
      base_url: url,
      api_key: api_key
    } do
      event_id = "evt_e2e_dup_#{System.unique_integer([:positive])}"

      payload = %{
        "id" => event_id,
        "type" => "invoice.paid",
        "data" => %{"object" => %{"id" => "in_e2e"}}
      }

      # First request — new event
      {:ok, resp1} =
        Req.post("#{url}/api/webhook-handler",
          json: payload,
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp1.status == 200
      assert resp1.body["received"] == true

      # Second request — same event ID (duplicate)
      {:ok, resp2} =
        Req.post("#{url}/api/webhook-handler",
          json: payload,
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp2.status == 200
      assert resp2.body["received"] == true
      assert resp2.body["status"] == "duplicate"
    end

    test "returns 401 without API key", %{base_url: url} do
      {:ok, resp} =
        Req.post("#{url}/api/webhook-handler",
          json: %{"id" => "evt_no_auth", "type" => "invoice.paid", "data" => %{}},
          retry: false
        )

      assert resp.status == 401
    end

    test "returns 400 for missing event id", %{base_url: url, api_key: api_key} do
      {:ok, resp} =
        Req.post("#{url}/api/webhook-handler",
          json: %{"type" => "invoice.paid", "data" => %{}},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 400
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
