defmodule SLEWeb.Plugs.TenantScope do
  @moduledoc """
  Plug that copies `current_tenant.id` to `conn.assigns.tenant_id`.

  Must run AFTER `SLEWeb.Plugs.Auth`. If no `current_tenant` is
  assigned, halts with 401.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case conn.assigns do
      %{current_tenant: %{id: tenant_id}} ->
        assign(conn, :tenant_id, tenant_id)

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(unauthorized_body()))
        |> halt()
    end
  end

  defp unauthorized_body do
    %{
      error: %{
        code: "UNAUTHORIZED",
        message: "Invalid or missing API key"
      }
    }
  end
end
