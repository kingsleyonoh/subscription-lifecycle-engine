defmodule SLEWeb.Plugs.RateLimitTest do
  @moduledoc """
  Tests for the rate limiting plug.

  Verifies ETS-based sliding window rate limiting per {tenant_id, endpoint}
  with configurable limits, 429 responses when exceeded, and global
  (unauthenticated) rate limiting by IP.
  """

  use SLEWeb.ConnCase, async: false

  import SLE.Factory

  alias SLEWeb.Plugs.RateLimit

  setup do
    # Clear rate limit state between tests
    RateLimit.reset_all()
    :ok
  end

  describe "init/1" do
    test "accepts limit and window_ms options" do
      opts = RateLimit.init(limit: 10, window_ms: 60_000)
      assert opts[:limit] == 10
      assert opts[:window_ms] == 60_000
    end

    test "uses default values when no options provided" do
      opts = RateLimit.init([])
      assert opts[:limit] == 100
      assert opts[:window_ms] == 60_000
    end
  end

  describe "call/2 with authenticated tenant" do
    setup do
      tenant = insert(:tenant)
      {:ok, tenant: tenant}
    end

    test "allows requests within limit", %{conn: conn, tenant: tenant} do
      opts = RateLimit.init(limit: 5, window_ms: 60_000)

      conn =
        conn
        |> assign(:current_tenant, tenant)
        |> Map.put(:request_path, "/api/tenants/me")
        |> RateLimit.call(opts)

      refute conn.halted
    end

    test "returns 429 when limit exceeded", %{conn: conn, tenant: tenant} do
      opts = RateLimit.init(limit: 2, window_ms: 60_000)

      # Use up the limit
      for _ <- 1..2 do
        conn
        |> assign(:current_tenant, tenant)
        |> Map.put(:request_path, "/api/tenants/me")
        |> RateLimit.call(opts)
      end

      # This request should be rate limited
      result =
        conn
        |> assign(:current_tenant, tenant)
        |> Map.put(:request_path, "/api/tenants/me")
        |> RateLimit.call(opts)

      assert result.halted
      assert result.status == 429

      body = Jason.decode!(result.resp_body)
      assert body["error"]["code"] == "RATE_LIMITED"
      assert body["error"]["message"] == "Too many requests"
    end

    test "rate limits are scoped per tenant", %{conn: conn, tenant: tenant} do
      other_tenant = insert(:tenant)
      opts = RateLimit.init(limit: 1, window_ms: 60_000)

      # Exhaust limit for first tenant
      conn
      |> assign(:current_tenant, tenant)
      |> Map.put(:request_path, "/api/tenants/me")
      |> RateLimit.call(opts)

      # Second tenant should still be allowed
      result =
        conn
        |> assign(:current_tenant, other_tenant)
        |> Map.put(:request_path, "/api/tenants/me")
        |> RateLimit.call(opts)

      refute result.halted
    end

    test "rate limits are scoped per endpoint", %{conn: conn, tenant: tenant} do
      opts = RateLimit.init(limit: 1, window_ms: 60_000)

      # Exhaust limit for one endpoint
      conn
      |> assign(:current_tenant, tenant)
      |> Map.put(:request_path, "/api/tenants/me")
      |> RateLimit.call(opts)

      # Different endpoint should still be allowed
      result =
        conn
        |> assign(:current_tenant, tenant)
        |> Map.put(:request_path, "/api/subscriptions")
        |> RateLimit.call(opts)

      refute result.halted
    end
  end

  describe "call/2 with unauthenticated (global by IP)" do
    test "rate limits by remote IP when no tenant assigned", %{conn: conn} do
      opts = RateLimit.init(limit: 2, window_ms: 60_000)

      # Exhaust the limit
      for _ <- 1..2 do
        conn
        |> Map.put(:request_path, "/api/tenants/register")
        |> RateLimit.call(opts)
      end

      # Next request should be rate limited
      result =
        conn
        |> Map.put(:request_path, "/api/tenants/register")
        |> RateLimit.call(opts)

      assert result.halted
      assert result.status == 429
    end
  end

  describe "window expiry" do
    test "allows requests after window expires", %{conn: conn} do
      opts = RateLimit.init(limit: 1, window_ms: 50)

      tenant = insert(:tenant)

      # Exhaust the limit
      conn
      |> assign(:current_tenant, tenant)
      |> Map.put(:request_path, "/api/test")
      |> RateLimit.call(opts)

      # Wait for window to expire
      Process.sleep(60)

      # Should be allowed again
      result =
        conn
        |> assign(:current_tenant, tenant)
        |> Map.put(:request_path, "/api/test")
        |> RateLimit.call(opts)

      refute result.halted
    end
  end

  describe "reset_all/0" do
    test "clears all rate limit counters", %{conn: conn} do
      opts = RateLimit.init(limit: 1, window_ms: 60_000)
      tenant = insert(:tenant)

      # Exhaust the limit
      conn
      |> assign(:current_tenant, tenant)
      |> Map.put(:request_path, "/api/test")
      |> RateLimit.call(opts)

      # Reset
      RateLimit.reset_all()

      # Should be allowed again
      result =
        conn
        |> assign(:current_tenant, tenant)
        |> Map.put(:request_path, "/api/test")
        |> RateLimit.call(opts)

      refute result.halted
    end
  end
end
