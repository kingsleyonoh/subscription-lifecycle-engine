defmodule SLEWeb.CustomerControllerTest do
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

  describe "GET /api/customers" do
    test "returns empty list when no customers exist", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers")

      resp = json_response(conn, 200)
      assert resp["data"] == []
      assert resp["meta"]["hasMore"] == false
      assert resp["meta"]["cursor"] == nil
    end

    test "returns customers for tenant", %{conn: conn, api_key: api_key, tenant: tenant} do
      insert(:customer, tenant_id: tenant.id, name: "Alice")
      insert(:customer, tenant_id: tenant.id, name: "Bob")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers")

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 2
    end

    test "supports cursor pagination", %{conn: conn, api_key: api_key, tenant: tenant} do
      for _i <- 1..5 do
        insert(:customer, tenant_id: tenant.id)
      end

      conn1 =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers", %{"limit" => "3"})

      resp1 = json_response(conn1, 200)
      assert length(resp1["data"]) == 3
      assert resp1["meta"]["hasMore"] == true

      conn2 =
        build_conn()
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers", %{"limit" => "3", "cursor" => resp1["meta"]["cursor"]})

      resp2 = json_response(conn2, 200)
      assert length(resp2["data"]) == 2
      assert resp2["meta"]["hasMore"] == false

      ids1 = Enum.map(resp1["data"], & &1["id"])
      ids2 = Enum.map(resp2["data"], & &1["id"])
      assert MapSet.disjoint?(MapSet.new(ids1), MapSet.new(ids2))
    end

    test "does not return customers from other tenants", %{conn: conn, api_key: api_key} do
      other_tenant = insert(:tenant)
      insert(:customer, tenant_id: other_tenant.id)

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers")

      resp = json_response(conn, 200)
      assert resp["data"] == []
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/customers")
      assert json_response(conn, 401)
    end

    test "response includes customer fields", %{conn: conn, api_key: api_key, tenant: tenant} do
      customer =
        insert(:customer, tenant_id: tenant.id, name: "Alice", email: "alice@example.com")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers")

      [item] = json_response(conn, 200)["data"]
      assert item["id"] == customer.id
      assert item["name"] == "Alice"
      assert item["email"] == "alice@example.com"
      assert item["stripeCustomerId"] == customer.stripe_customer_id
      assert is_binary(item["insertedAt"])
    end
  end

  describe "GET /api/customers/:id" do
    test "returns customer with subscriptions", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      customer = insert(:customer, tenant_id: tenant.id, name: "Alice")
      plan = insert(:plan, tenant_id: tenant.id, name: "Pro Plan")

      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "active"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers/#{customer.id}")

      resp = json_response(conn, 200)
      assert resp["customer"]["id"] == customer.id
      assert resp["customer"]["name"] == "Alice"
      assert length(resp["subscriptions"]) == 1
      assert hd(resp["subscriptions"])["status"] == "active"
      assert hd(resp["subscriptions"])["plan"]["name"] == "Pro Plan"
    end

    test "returns 404 for non-existent customer", %{conn: conn, api_key: api_key} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers/#{fake_id}")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 404 for customer belonging to another tenant", %{
      conn: conn,
      api_key: api_key
    } do
      other_tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: other_tenant.id)

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers/#{customer.id}")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns customer with empty subscriptions list", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      customer = insert(:customer, tenant_id: tenant.id)

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/customers/#{customer.id}")

      resp = json_response(conn, 200)
      assert resp["customer"]["id"] == customer.id
      assert resp["subscriptions"] == []
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/customers/#{Ecto.UUID.generate()}")
      assert json_response(conn, 401)
    end
  end
end
