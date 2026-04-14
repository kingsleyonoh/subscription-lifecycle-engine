defmodule SLEWeb.SubscriptionControllerTest do
  @moduledoc false

  use SLEWeb.ConnCase, async: true

  import SLE.Factory

  setup do
    SLEWeb.Plugs.RateLimit.reset_all()

    unique = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    api_key = "sle_live_" <> unique
    hash = :crypto.hash(:sha256, api_key) |> Base.encode16(case: :lower)
    prefix = String.slice(api_key, 0, 13)

    tenant = insert(:tenant, api_key_hash: hash, api_key_prefix: prefix)

    {:ok, tenant: tenant, api_key: api_key}
  end

  describe "GET /api/subscriptions" do
    test "returns empty list when no subscriptions exist", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions")

      resp = json_response(conn, 200)
      assert resp["data"] == []
      assert resp["meta"]["hasMore"] == false
      assert resp["meta"]["cursor"] == nil
    end

    test "returns subscriptions for tenant", %{conn: conn, api_key: api_key, tenant: tenant} do
      customer = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        status: "active"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions")

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
      assert hd(resp["data"])["status"] == "active"
    end

    test "filters by status", %{conn: conn, api_key: api_key, tenant: tenant} do
      customer = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        status: "active"
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        status: "trialing"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions", %{"status" => "active"})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
      assert hd(resp["data"])["status"] == "active"
    end

    test "filters by customer_id", %{conn: conn, api_key: api_key, tenant: tenant} do
      customer1 = insert(:customer, tenant_id: tenant.id)
      customer2 = insert(:customer, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer1.id,
        status: "active"
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer2.id,
        status: "active"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions", %{"customer_id" => customer1.id})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
    end

    test "filters by plan_id", %{conn: conn, api_key: api_key, tenant: tenant} do
      customer = insert(:customer, tenant_id: tenant.id)
      plan1 = insert(:plan, tenant_id: tenant.id)
      plan2 = insert(:plan, tenant_id: tenant.id)

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan1.id,
        status: "active"
      )

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan2.id,
        status: "active"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions", %{"plan_id" => plan1.id})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
    end

    test "supports cursor pagination", %{conn: conn, api_key: api_key, tenant: tenant} do
      customer = insert(:customer, tenant_id: tenant.id)

      for _i <- 1..5 do
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          status: "active"
        )
      end

      # Page 1
      conn1 =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions", %{"limit" => "3"})

      resp1 = json_response(conn1, 200)
      assert length(resp1["data"]) == 3
      assert resp1["meta"]["hasMore"] == true

      # Page 2
      conn2 =
        build_conn()
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions", %{"limit" => "3", "cursor" => resp1["meta"]["cursor"]})

      resp2 = json_response(conn2, 200)
      assert length(resp2["data"]) == 2
      assert resp2["meta"]["hasMore"] == false

      # No overlap between pages
      ids1 = Enum.map(resp1["data"], & &1["id"])
      ids2 = Enum.map(resp2["data"], & &1["id"])
      assert MapSet.disjoint?(MapSet.new(ids1), MapSet.new(ids2))
    end

    test "does not return subscriptions from other tenants", %{
      conn: conn,
      api_key: api_key
    } do
      other_tenant = insert(:tenant)
      other_customer = insert(:customer, tenant_id: other_tenant.id)

      insert(:subscription,
        tenant_id: other_tenant.id,
        customer_id: other_customer.id,
        status: "active"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions")

      resp = json_response(conn, 200)
      assert resp["data"] == []
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/subscriptions")
      assert json_response(conn, 401)
    end

    test "response includes subscription fields", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id)

      sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: customer.id,
          plan_id: plan.id,
          status: "active",
          cancel_at_period_end: false
        )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/subscriptions")

      [item] = json_response(conn, 200)["data"]
      assert item["id"] == sub.id
      assert item["status"] == "active"
      assert item["stripe_subscription_id"] == sub.stripe_subscription_id
      assert item["cancel_at_period_end"] == false
      assert is_binary(item["current_period_start"])
      assert is_binary(item["current_period_end"])
    end
  end
end
