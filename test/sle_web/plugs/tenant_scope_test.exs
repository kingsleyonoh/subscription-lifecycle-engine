defmodule SLEWeb.Plugs.TenantScopeTest do
  use SLEWeb.ConnCase, async: true

  @moduledoc false

  alias SLEWeb.Plugs.TenantScope

  describe "call/2 with current_tenant assigned" do
    test "sets tenant_id from current_tenant" do
      tenant_id = Ecto.UUID.generate()
      tenant = %{id: tenant_id, name: "Scope Test"}

      conn =
        build_conn()
        |> assign(:current_tenant, tenant)
        |> TenantScope.call(TenantScope.init([]))

      assert conn.assigns.tenant_id == tenant_id
      refute conn.halted
    end
  end

  describe "call/2 without current_tenant" do
    test "halts with 401 error when no current_tenant assigned" do
      conn =
        build_conn()
        |> TenantScope.call(TenantScope.init([]))

      assert conn.halted
      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "UNAUTHORIZED"
    end
  end
end
