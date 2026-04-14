defmodule SLEWeb.TenantControllerTest do
  @moduledoc """
  Tests for the tenant controller endpoints:
  - POST /api/tenants/register (public)
  - GET /api/tenants/me (authenticated)
  """

  use SLEWeb.ConnCase, async: true

  import SLE.Factory

  describe "POST /api/tenants/register" do
    test "creates tenant and returns plaintext API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/tenants/register", %{"name" => "My SaaS"})

      assert %{
               "id" => id,
               "name" => "My SaaS",
               "apiKey" => api_key
             } = json_response(conn, 201)

      assert is_binary(id)
      assert String.starts_with?(api_key, "sle_live_")
    end

    test "returns 400 when name is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/tenants/register", %{})

      assert %{"error" => %{"code" => "VALIDATION_ERROR"}} = json_response(conn, 400)
    end

    test "returns 400 when name is blank", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/tenants/register", %{"name" => ""})

      assert %{"error" => %{"code" => "VALIDATION_ERROR"}} = json_response(conn, 400)
    end

    test "returns 403 when registration is disabled", %{conn: conn} do
      # Temporarily disable registration
      original = Application.get_env(:sle, :self_registration_enabled, true)
      Application.put_env(:sle, :self_registration_enabled, false)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/tenants/register", %{"name" => "Test"})

      assert %{"error" => %{"code" => "FORBIDDEN"}} = json_response(conn, 403)

      # Restore original setting
      Application.put_env(:sle, :self_registration_enabled, original)
    end

    test "created tenant can authenticate", %{conn: conn} do
      # Register a tenant
      register_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/tenants/register", %{"name" => "Auth Test SaaS"})

      %{"apiKey" => api_key} = json_response(register_conn, 201)

      # Use the API key to authenticate
      me_conn =
        build_conn()
        |> put_req_header("x-api-key", api_key)
        |> get("/api/tenants/me")

      assert %{"name" => "Auth Test SaaS"} = json_response(me_conn, 200)
    end
  end

  describe "GET /api/tenants/me" do
    setup do
      # Generate a unique API key for this test run
      unique = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
      api_key = "sle_live_" <> unique
      hash = :crypto.hash(:sha256, api_key) |> Base.encode16(case: :lower)
      prefix = String.slice(api_key, 0, 13)

      tenant = insert(:tenant, api_key_hash: hash, api_key_prefix: prefix)

      {:ok, tenant: tenant, api_key: api_key}
    end

    test "returns tenant profile with correct fields", %{
      conn: conn,
      tenant: tenant,
      api_key: api_key
    } do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/tenants/me")

      assert %{
               "id" => id,
               "name" => name,
               "apiKeyPrefix" => api_key_prefix,
               "isActive" => is_active,
               "createdAt" => created_at
             } = json_response(conn, 200)

      assert id == tenant.id
      assert name == tenant.name
      assert api_key_prefix == tenant.api_key_prefix
      assert is_active == true
      assert is_binary(created_at)
    end

    test "returns 401 without API key", %{conn: conn} do
      conn = get(conn, "/api/tenants/me")

      assert %{"error" => %{"code" => "UNAUTHORIZED"}} = json_response(conn, 401)
    end

    test "returns 401 with invalid API key", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-api-key", "invalid_key")
        |> get("/api/tenants/me")

      assert %{"error" => %{"code" => "UNAUTHORIZED"}} = json_response(conn, 401)
    end

    test "does not return the full API key hash", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> get("/api/tenants/me")

      body = json_response(conn, 200)
      refute Map.has_key?(body, "apiKeyHash")
      refute Map.has_key?(body, "api_key_hash")
    end
  end
end
