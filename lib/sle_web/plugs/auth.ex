defmodule SLEWeb.Plugs.Auth do
  @moduledoc """
  Plug that authenticates requests via the `X-API-Key` header.

  Extracts the API key, calls `SLE.Tenants.authenticate/1`, and
  sets `conn.assigns.current_tenant` on success. Halts with 401
  on failure.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn
    |> get_api_key()
    |> authenticate(conn)
  end

  defp get_api_key(conn) do
    case get_req_header(conn, "x-api-key") do
      [key | _] -> key
      [] -> nil
    end
  end

  defp authenticate(api_key, conn) do
    case SLE.Tenants.authenticate(api_key) do
      {:ok, tenant} ->
        assign(conn, :current_tenant, tenant)

      {:error, :unauthorized} ->
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
