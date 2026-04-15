defmodule SLE.E2E.PlanE2ETest do
  @moduledoc """
  E2E tests for plan API endpoints hitting a running HTTP server.

  Tests the full CRUD lifecycle: create, list, update.
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
    {:ok, reg} =
      Req.post("#{url}/api/tenants/register",
        json: %{"name" => "E2E Plan Test"},
        retry: false
      )

    api_key = reg.body["apiKey"]
    %{api_key: api_key}
  end

  describe "plan CRUD lifecycle" do
    test "create, list, and update a plan", %{base_url: url, api_key: api_key} do
      # Create a plan
      {:ok, create_resp} =
        Req.post("#{url}/api/plans",
          json: %{
            "stripe_price_id" => "price_e2e_#{System.unique_integer([:positive])}",
            "name" => "E2E Pro Plan",
            "amount_cents" => 2999,
            "interval" => "month"
          },
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert create_resp.status == 201
      assert create_resp.body["name"] == "E2E Pro Plan"
      assert create_resp.body["amount_cents"] == 2999
      plan_id = create_resp.body["id"]

      # List plans — should include the created plan
      {:ok, list_resp} =
        Req.get("#{url}/api/plans",
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert list_resp.status == 200
      plan_ids = Enum.map(list_resp.body["data"], & &1["id"])
      assert plan_id in plan_ids

      # Update the plan name
      {:ok, update_resp} =
        Req.put("#{url}/api/plans/#{plan_id}",
          json: %{"name" => "E2E Enterprise Plan"},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert update_resp.status == 200
      assert update_resp.body["name"] == "E2E Enterprise Plan"
      assert update_resp.body["id"] == plan_id
    end

    test "returns 401 without API key", %{base_url: url} do
      {:ok, resp} =
        Req.get("#{url}/api/plans", retry: false)

      assert resp.status == 401
    end

    test "returns 400 for invalid plan creation", %{base_url: url, api_key: api_key} do
      {:ok, resp} =
        Req.post("#{url}/api/plans",
          json: %{},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 400
    end

    test "returns 404 for non-existent plan update", %{base_url: url, api_key: api_key} do
      fake_id = Ecto.UUID.generate()

      {:ok, resp} =
        Req.put("#{url}/api/plans/#{fake_id}",
          json: %{"name" => "X"},
          headers: [{"x-api-key", api_key}],
          retry: false
        )

      assert resp.status == 404
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
