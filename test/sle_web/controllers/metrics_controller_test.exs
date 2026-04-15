defmodule SLEWeb.MetricsControllerTest do
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

  describe "GET /api/metrics/overview" do
    test "returns latest snapshot data", %{conn: conn, api_key: api_key, tenant: tenant} do
      insert(:metrics_snapshot,
        tenant_id: tenant.id,
        period_start: ~D[2026-04-13],
        period_end: ~D[2026-04-14],
        mrr_cents: 50_000,
        arr_cents: 600_000,
        active_count: 25,
        trialing_count: 3,
        churned_count: 2,
        churn_rate: Decimal.new("0.0741"),
        dunning_active: 1,
        arpu_cents: 2000,
        computed_at: ~U[2026-04-14 02:00:00Z]
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/overview")

      resp = json_response(conn, 200)
      assert resp["mrrCents"] == 50_000
      assert resp["arrCents"] == 600_000
      assert resp["activeCount"] == 25
      assert resp["trialingCount"] == 3
      assert resp["churnRate"] != nil
      assert resp["dunningActive"] == 1
      assert resp["arpuCents"] == 2000
    end

    test "returns 404 when no snapshot exists", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/overview")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/metrics/overview")
      assert json_response(conn, 401)
    end

    test "does not return snapshots from other tenants", %{
      conn: conn,
      api_key: api_key
    } do
      other_tenant = insert(:tenant)

      insert(:metrics_snapshot,
        tenant_id: other_tenant.id,
        period_start: ~D[2026-04-13],
        period_end: ~D[2026-04-14],
        mrr_cents: 99_999,
        computed_at: ~U[2026-04-14 02:00:00Z]
      )

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/overview")

      assert %{"error" => %{"code" => "NOT_FOUND"}} = json_response(conn, 404)
    end
  end

  describe "GET /api/metrics/mrr" do
    test "returns MRR time series with default 30d period", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      today = Date.utc_today()

      for i <- 0..4 do
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          period_start: Date.add(today, -(i + 1)),
          period_end: Date.add(today, -i),
          mrr_cents: 10_000 + i * 1000,
          computed_at:
            DateTime.new!(Date.add(today, -i), ~T[02:00:00Z]) |> DateTime.truncate(:second)
        )
      end

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/mrr")

      resp = json_response(conn, 200)
      assert is_list(resp["data"])
      assert length(resp["data"]) == 5

      first = hd(resp["data"])
      assert Map.has_key?(first, "date")
      assert Map.has_key?(first, "mrrCents")
    end

    test "respects period parameter", %{conn: conn, api_key: api_key, tenant: tenant} do
      today = Date.utc_today()

      for i <- 0..10 do
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          period_start: Date.add(today, -(i + 1)),
          period_end: Date.add(today, -i),
          mrr_cents: 10_000,
          computed_at:
            DateTime.new!(Date.add(today, -i), ~T[02:00:00Z]) |> DateTime.truncate(:second)
        )
      end

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/mrr", %{"period" => "7d"})

      resp = json_response(conn, 200)
      # 7d window: cutoff = today - 7. period_end > cutoff means 7 results
      assert length(resp["data"]) == 7
    end

    test "returns empty array when no snapshots", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/mrr")

      resp = json_response(conn, 200)
      assert resp["data"] == []
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/metrics/mrr")
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/metrics/churn" do
    test "returns churn rate time series with default 90d period", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      today = Date.utc_today()

      for i <- 0..4 do
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          period_start: Date.add(today, -(i + 1)),
          period_end: Date.add(today, -i),
          mrr_cents: 10_000,
          churn_rate: Decimal.new("0.0500"),
          churned_count: 1,
          computed_at:
            DateTime.new!(Date.add(today, -i), ~T[02:00:00Z]) |> DateTime.truncate(:second)
        )
      end

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/churn")

      resp = json_response(conn, 200)
      assert is_list(resp["data"])
      assert length(resp["data"]) == 5

      first = hd(resp["data"])
      assert Map.has_key?(first, "date")
      assert Map.has_key?(first, "churnRate")
    end

    test "respects period parameter", %{conn: conn, api_key: api_key, tenant: tenant} do
      today = Date.utc_today()

      for i <- 0..30 do
        insert(:metrics_snapshot,
          tenant_id: tenant.id,
          period_start: Date.add(today, -(i + 1)),
          period_end: Date.add(today, -i),
          mrr_cents: 10_000,
          churn_rate: Decimal.new("0.0300"),
          computed_at:
            DateTime.new!(Date.add(today, -i), ~T[02:00:00Z]) |> DateTime.truncate(:second)
        )
      end

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/churn", %{"period" => "14d"})

      resp = json_response(conn, 200)
      # 14d window: cutoff = today - 14. period_end > cutoff means 14 results
      assert length(resp["data"]) == 14
    end

    test "returns empty array when no snapshots", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/metrics/churn")

      resp = json_response(conn, 200)
      assert resp["data"] == []
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/metrics/churn")
      assert json_response(conn, 401)
    end
  end
end
