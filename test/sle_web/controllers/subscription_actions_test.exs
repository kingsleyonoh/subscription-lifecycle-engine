defmodule SLEWeb.SubscriptionActionsTest do
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
    customer = insert(:customer, tenant_id: tenant.id)

    {:ok, tenant: tenant, api_key: api_key, customer: customer}
  end

  describe "POST /api/subscriptions/:id/cancel" do
    test "cancels at period end", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/cancel", %{"at_period_end" => true})

      resp = json_response(conn, 200)
      assert resp["subscription"]["cancel_at_period_end"] == true
    end

    test "cancels immediately", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/cancel", %{"at_period_end" => false})

      resp = json_response(conn, 200)
      assert resp["subscription"]["status"] == "canceled"
    end

    test "returns 404 for non-existent subscription", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{Ecto.UUID.generate()}/cancel", %{"at_period_end" => true})

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 409 for invalid transition (already canceled)", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "canceled")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/cancel", %{"at_period_end" => false})

      assert %{"error" => %{"code" => "CONFLICT"}} = json_response(conn, 409)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = post(conn, "/api/subscriptions/#{Ecto.UUID.generate()}/cancel", %{})
      assert json_response(conn, 401)
    end

    test "does not cancel subscription from another tenant", %{conn: conn, api_key: api_key} do
      other_tenant = insert(:tenant)
      other_customer = insert(:customer, tenant_id: other_tenant.id)

      sub =
        insert(:subscription,
          tenant_id: other_tenant.id,
          customer_id: other_customer.id,
          status: "active"
        )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/cancel", %{"at_period_end" => true})

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end
  end

  describe "POST /api/subscriptions/:id/pause" do
    test "pauses an active subscription", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/pause")

      resp = json_response(conn, 200)
      assert resp["subscription"]["status"] == "paused"
    end

    test "returns 409 for past_due subscription", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "past_due")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/pause")

      assert %{"error" => %{"code" => "CONFLICT"}} = json_response(conn, 409)
    end

    test "returns 409 for invalid transition (already paused)", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "paused")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/pause")

      assert %{"error" => %{"code" => "CONFLICT"}} = json_response(conn, 409)
    end

    test "returns 404 for non-existent subscription", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{Ecto.UUID.generate()}/pause")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = post(conn, "/api/subscriptions/#{Ecto.UUID.generate()}/pause")
      assert json_response(conn, 401)
    end
  end

  describe "POST /api/subscriptions/:id/resume" do
    test "resumes a paused subscription", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "paused")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/resume")

      resp = json_response(conn, 200)
      assert resp["subscription"]["status"] == "active"
    end

    test "returns 409 for non-paused subscription", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub =
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "active")

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{sub.id}/resume")

      assert %{"error" => %{"code" => "CONFLICT"}} = json_response(conn, 409)
    end

    test "returns 404 for non-existent subscription", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> post("/api/subscriptions/#{Ecto.UUID.generate()}/resume")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = post(conn, "/api/subscriptions/#{Ecto.UUID.generate()}/resume")
      assert json_response(conn, 401)
    end
  end
end
