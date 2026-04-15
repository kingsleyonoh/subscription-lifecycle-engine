defmodule SLEWeb.Plugs.AuthTest do
  use SLEWeb.ConnCase, async: true

  @moduledoc false

  alias SLEWeb.Plugs.Auth

  setup do
    {:ok, tenant, api_key} = SLE.Tenants.register(%{name: "Auth Plug Test"})
    SLE.Cache.clear()
    {:ok, tenant: tenant, api_key: api_key}
  end

  describe "call/2 with valid API key" do
    test "sets current_tenant on conn assigns", %{tenant: tenant, api_key: api_key} do
      conn =
        build_conn()
        |> put_req_header("x-api-key", api_key)
        |> Auth.call(Auth.init([]))

      assert conn.assigns.current_tenant.id == tenant.id
      refute conn.halted
    end
  end

  describe "call/2 with missing API key header" do
    test "halts with 401 error" do
      conn =
        build_conn()
        |> Auth.call(Auth.init([]))

      assert conn.halted
      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "UNAUTHORIZED"
      assert body["error"]["message"] == "Invalid or missing API key"
    end
  end

  describe "call/2 with invalid API key" do
    test "halts with 401 error" do
      conn =
        build_conn()
        |> put_req_header("x-api-key", "sle_live_totally_invalid_key_99")
        |> Auth.call(Auth.init([]))

      assert conn.halted
      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "UNAUTHORIZED"
    end
  end

  describe "call/2 with inactive tenant" do
    test "halts with 401 error", %{tenant: tenant, api_key: api_key} do
      # Deactivate
      tenant
      |> Ecto.Changeset.change(%{is_active: false})
      |> SLE.Repo.update!()

      SLE.Cache.clear()

      conn =
        build_conn()
        |> put_req_header("x-api-key", api_key)
        |> Auth.call(Auth.init([]))

      assert conn.halted
      assert conn.status == 401
    end
  end
end
