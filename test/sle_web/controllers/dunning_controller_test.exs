defmodule SLEWeb.DunningControllerTest do
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

    sub =
      insert(:subscription, tenant_id: tenant.id, customer_id: customer.id, status: "past_due")

    {:ok, tenant: tenant, api_key: api_key, customer: customer, subscription: sub}
  end

  describe "GET /api/dunning" do
    test "returns empty list when no dunning attempts", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning")

      resp = json_response(conn, 200)
      assert resp["data"] == []
      assert resp["meta"]["hasMore"] == false
      assert resp["meta"]["cursor"] == nil
    end

    test "returns dunning attempts for tenant", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer,
      subscription: sub
    } do
      invoice =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        invoice_id: invoice.id,
        customer_id: customer.id,
        status: "retrying",
        notification_payload: %{"template" => "dunning.payment_failed.first"}
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning")

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
      assert hd(resp["data"])["status"] == "retrying"
    end

    test "filters by status", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer,
      subscription: sub
    } do
      inv1 =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      inv2 =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        invoice_id: inv1.id,
        customer_id: customer.id,
        status: "pending",
        notification_payload: %{}
      )

      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        invoice_id: inv2.id,
        customer_id: customer.id,
        status: "retrying",
        notification_payload: %{}
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning", %{"status" => "retrying"})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
      assert hd(resp["data"])["status"] == "retrying"
    end

    test "filters by subscription_id", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer,
      subscription: sub
    } do
      inv1 =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        invoice_id: inv1.id,
        customer_id: customer.id,
        status: "pending",
        notification_payload: %{}
      )

      # Create another sub with dunning
      other_customer = insert(:customer, tenant_id: tenant.id)

      other_sub =
        insert(:subscription,
          tenant_id: tenant.id,
          customer_id: other_customer.id,
          status: "past_due"
        )

      other_inv =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: other_sub.id,
          customer_id: other_customer.id,
          status: "open"
        )

      insert(:dunning_attempt,
        tenant_id: tenant.id,
        subscription_id: other_sub.id,
        invoice_id: other_inv.id,
        customer_id: other_customer.id,
        status: "pending",
        notification_payload: %{}
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning", %{"subscription_id" => sub.id})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 1
    end

    test "supports cursor pagination", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer,
      subscription: sub
    } do
      for _i <- 1..5 do
        inv =
          insert(:invoice,
            tenant_id: tenant.id,
            subscription_id: sub.id,
            customer_id: customer.id,
            status: "open"
          )

        insert(:dunning_attempt,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          invoice_id: inv.id,
          customer_id: customer.id,
          status: "pending",
          notification_payload: %{}
        )
      end

      conn1 =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning", %{"limit" => "3"})

      resp1 = json_response(conn1, 200)
      assert length(resp1["data"]) == 3
      assert resp1["meta"]["hasMore"] == true

      conn2 =
        build_conn()
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning", %{"limit" => "3", "cursor" => resp1["meta"]["cursor"]})

      resp2 = json_response(conn2, 200)
      assert length(resp2["data"]) == 2
      assert resp2["meta"]["hasMore"] == false
    end

    test "does not return dunning from other tenants", %{conn: conn, api_key: api_key} do
      other_tenant = insert(:tenant)
      other_customer = insert(:customer, tenant_id: other_tenant.id)

      other_sub =
        insert(:subscription,
          tenant_id: other_tenant.id,
          customer_id: other_customer.id,
          status: "past_due"
        )

      other_inv =
        insert(:invoice,
          tenant_id: other_tenant.id,
          subscription_id: other_sub.id,
          customer_id: other_customer.id,
          status: "open"
        )

      insert(:dunning_attempt,
        tenant_id: other_tenant.id,
        subscription_id: other_sub.id,
        invoice_id: other_inv.id,
        customer_id: other_customer.id,
        status: "pending",
        notification_payload: %{}
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning")

      resp = json_response(conn, 200)
      assert resp["data"] == []
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/dunning")
      assert json_response(conn, 401)
    end

    test "response includes dunning fields", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer,
      subscription: sub
    } do
      inv =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      da =
        insert(:dunning_attempt,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          invoice_id: inv.id,
          customer_id: customer.id,
          status: "retrying",
          attempt_number: 2,
          max_attempts: 4,
          escalation_channel: "email",
          notification_payload: %{"template" => "test"}
        )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning")

      [item] = json_response(conn, 200)["data"]
      assert item["id"] == da.id
      assert item["status"] == "retrying"
      assert item["attemptNumber"] == 2
      assert item["maxAttempts"] == 4
      assert item["escalationChannel"] == "email"
      assert item["subscriptionId"] == sub.id
      assert item["invoiceId"] == inv.id
    end
  end

  describe "GET /api/dunning/:id" do
    test "returns dunning detail with error_log", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant,
      customer: customer,
      subscription: sub
    } do
      inv =
        insert(:invoice,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          customer_id: customer.id,
          status: "open"
        )

      da =
        insert(:dunning_attempt,
          tenant_id: tenant.id,
          subscription_id: sub.id,
          invoice_id: inv.id,
          customer_id: customer.id,
          status: "retrying",
          attempt_number: 2,
          error_log: [%{"message" => "Card declined", "at" => "2026-01-01T00:00:00Z"}],
          notification_payload: %{"template" => "test"}
        )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning/#{da.id}")

      resp = json_response(conn, 200)
      assert resp["dunning"]["id"] == da.id
      assert resp["dunning"]["status"] == "retrying"
      assert length(resp["dunning"]["errorLog"]) == 1
      assert hd(resp["dunning"]["errorLog"])["message"] == "Card declined"
    end

    test "returns 404 for non-existent dunning", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning/#{Ecto.UUID.generate()}")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 404 for dunning belonging to another tenant", %{conn: conn, api_key: api_key} do
      other_tenant = insert(:tenant)
      other_customer = insert(:customer, tenant_id: other_tenant.id)

      other_sub =
        insert(:subscription,
          tenant_id: other_tenant.id,
          customer_id: other_customer.id,
          status: "past_due"
        )

      other_inv =
        insert(:invoice,
          tenant_id: other_tenant.id,
          subscription_id: other_sub.id,
          customer_id: other_customer.id,
          status: "open"
        )

      da =
        insert(:dunning_attempt,
          tenant_id: other_tenant.id,
          subscription_id: other_sub.id,
          invoice_id: other_inv.id,
          customer_id: other_customer.id,
          status: "pending",
          notification_payload: %{}
        )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/dunning/#{da.id}")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/dunning/#{Ecto.UUID.generate()}")
      assert json_response(conn, 401)
    end
  end
end
