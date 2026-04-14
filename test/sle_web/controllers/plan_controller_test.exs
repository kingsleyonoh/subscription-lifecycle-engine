defmodule SLEWeb.PlanControllerTest do
  @moduledoc """
  Tests for the plan API endpoints:
  - GET /api/plans
  - POST /api/plans
  - PUT /api/plans/:id
  """

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

  describe "GET /api/plans" do
    test "returns empty list when no plans exist", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/plans")

      assert json_response(conn, 200) == %{"data" => []}
    end

    test "returns active plans for tenant", %{conn: conn, api_key: api_key, tenant: tenant} do
      plan = insert(:plan, tenant_id: tenant.id, name: "Pro Plan")
      _inactive = insert(:plan, tenant_id: tenant.id, is_active: false, name: "Old Plan")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/plans")

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
      assert hd(resp["data"])["id"] == plan.id
      assert hd(resp["data"])["name"] == "Pro Plan"
    end

    test "includes inactive plans when requested", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      _active = insert(:plan, tenant_id: tenant.id, name: "Active Plan")
      _inactive = insert(:plan, tenant_id: tenant.id, is_active: false, name: "Old Plan")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/plans", %{"include_inactive" => "true"})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 2
    end

    test "does not return plans from other tenants", %{conn: conn, api_key: api_key} do
      other_tenant = insert(:tenant)
      _other_plan = insert(:plan, tenant_id: other_tenant.id, name: "Other Plan")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/plans")

      assert json_response(conn, 200) == %{"data" => []}
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/plans")
      assert json_response(conn, 401)
    end
  end

  describe "POST /api/plans" do
    test "creates a plan with valid attrs", %{conn: conn, api_key: api_key} do
      attrs = %{
        "stripe_price_id" => "price_new_1",
        "name" => "Starter Plan",
        "amount_cents" => 999,
        "interval" => "month"
      }

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", attrs)

      resp = json_response(conn, 201)
      assert resp["name"] == "Starter Plan"
      assert resp["stripe_price_id"] == "price_new_1"
      assert resp["amount_cents"] == 999
      assert resp["interval"] == "month"
      assert resp["is_active"] == true
      assert is_binary(resp["id"])
    end

    test "returns 400 when required fields are missing", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", %{})

      assert %{"error" => %{"code" => "VALIDATION_ERROR"}} = json_response(conn, 400)
    end

    test "returns 400 for invalid interval", %{conn: conn, api_key: api_key} do
      attrs = %{
        "stripe_price_id" => "price_bad_interval",
        "name" => "Bad Plan",
        "amount_cents" => 999,
        "interval" => "daily"
      }

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", attrs)

      assert %{"error" => %{"code" => "VALIDATION_ERROR"}} = json_response(conn, 400)
    end

    test "returns 400 for duplicate stripe_price_id within tenant", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      insert(:plan, tenant_id: tenant.id, stripe_price_id: "price_dup_1")

      attrs = %{
        "stripe_price_id" => "price_dup_1",
        "name" => "Duplicate Plan",
        "amount_cents" => 1999,
        "interval" => "month"
      }

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", attrs)

      assert %{"error" => %{"code" => "VALIDATION_ERROR"}} = json_response(conn, 400)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/plans", %{"name" => "X"})

      assert json_response(conn, 401)
    end
  end

  describe "PUT /api/plans/:id" do
    test "updates plan name", %{conn: conn, api_key: api_key, tenant: tenant} do
      plan = insert(:plan, tenant_id: tenant.id, name: "Old Name")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> put("/api/plans/#{plan.id}", %{"name" => "New Name"})

      resp = json_response(conn, 200)
      assert resp["name"] == "New Name"
      assert resp["id"] == plan.id
    end

    test "updates plan is_active", %{conn: conn, api_key: api_key, tenant: tenant} do
      plan = insert(:plan, tenant_id: tenant.id, is_active: true)

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> put("/api/plans/#{plan.id}", %{"is_active" => false})

      resp = json_response(conn, 200)
      assert resp["is_active"] == false
    end

    test "returns 404 for non-existent plan", %{conn: conn, api_key: api_key} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> put("/api/plans/#{fake_id}", %{"name" => "X"})

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 404 for plan belonging to another tenant", %{conn: conn, api_key: api_key} do
      other_tenant = insert(:tenant)
      plan = insert(:plan, tenant_id: other_tenant.id)

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> put("/api/plans/#{plan.id}", %{"name" => "Stolen"})

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/plans/#{Ecto.UUID.generate()}", %{"name" => "X"})

      assert json_response(conn, 401)
    end
  end
end
