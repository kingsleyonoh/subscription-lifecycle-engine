defmodule SLEWeb.InvoiceControllerTest do
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

  describe "GET /api/invoices" do
    test "returns empty list when no invoices exist", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices")

      resp = json_response(conn, 200)
      assert resp["data"] == []
      assert resp["meta"]["hasMore"] == false
      assert resp["meta"]["cursor"] == nil
    end

    test "returns invoices for tenant", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        status: "open"
      )

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        status: "paid"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices")

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 2
    end

    test "filters by status", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        status: "open"
      )

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        status: "paid"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices", %{"status" => "paid"})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
      assert hd(resp["data"])["status"] == "paid"
    end

    test "filters by subscription_id", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub1 = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)
      sub2 = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub1.id,
        customer_id: customer.id,
        status: "open"
      )

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub2.id,
        customer_id: customer.id,
        status: "open"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices", %{"subscription_id" => sub1.id})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
    end

    test "filters by since", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        status: "open"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices", %{"since" => "2099-01-01T00:00:00Z"})

      resp = json_response(conn, 200)
      assert resp["data"] == []
    end

    test "supports cursor pagination", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      for _i <- 1..5 do
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )
      end

      conn1 =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices", %{"limit" => "3"})

      resp1 = json_response(conn1, 200)
      assert length(resp1["data"]) == 3
      assert resp1["meta"]["hasMore"] == true

      conn2 =
        build_conn()
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices", %{"limit" => "3", "cursor" => resp1["meta"]["cursor"]})

      resp2 = json_response(conn2, 200)
      assert length(resp2["data"]) == 2
      assert resp2["meta"]["hasMore"] == false
    end

    test "does not return invoices from other tenants", %{conn: conn, api_key: api_key} do
      other_tenant = insert(:tenant)
      other_customer = insert(:customer, tenant_id: other_tenant.id)

      other_sub =
        insert(:subscription, tenant_id: other_tenant.id, customer_id: other_customer.id)

      insert(:invoice,
        tenant_id: other_tenant.id,
        subscription_id: other_sub.id,
        customer_id: other_customer.id,
        status: "open"
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices")

      resp = json_response(conn, 200)
      assert resp["data"] == []
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/invoices")
      assert json_response(conn, 401)
    end

    test "response includes invoice fields", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open",
          amount_due_cents: 2999,
          currency: "usd"
        )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices")

      [item] = json_response(conn, 200)["data"]
      assert item["id"] == invoice.id
      assert item["status"] == "open"
      assert item["amountDueCents"] == 2999
      assert item["currency"] == "usd"
      assert item["stripeInvoiceId"] == invoice.stripe_invoice_id
    end
  end

  describe "GET /api/invoices/:id" do
    test "returns invoice detail", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer
    } do
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "paid",
          amount_due_cents: 1999,
          amount_paid_cents: 1999
        )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices/#{invoice.id}")

      resp = json_response(conn, 200)
      assert resp["invoice"]["id"] == invoice.id
      assert resp["invoice"]["status"] == "paid"
      assert resp["invoice"]["amountDueCents"] == 1999
      assert resp["invoice"]["amountPaidCents"] == 1999
    end

    test "returns 404 for non-existent invoice", %{conn: conn, api_key: api_key} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices/#{fake_id}")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 404 for invoice belonging to another tenant", %{
      conn: conn,
      api_key: api_key
    } do
      other_tenant = insert(:tenant)
      other_customer = insert(:customer, tenant_id: other_tenant.id)

      other_sub =
        insert(:subscription, tenant_id: other_tenant.id, customer_id: other_customer.id)

      invoice =
        insert(:invoice,
          tenant_id: other_tenant.id,
          subscription_id: other_sub.id,
          customer_id: other_customer.id,
          status: "open"
        )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/invoices/#{invoice.id}")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/invoices/#{Ecto.UUID.generate()}")
      assert json_response(conn, 401)
    end
  end
end
