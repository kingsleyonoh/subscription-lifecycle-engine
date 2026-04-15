defmodule SLEWeb.TenantController do
  @moduledoc """
  Handles tenant registration (public) and tenant profile (authenticated).

  ## Endpoints

    * `POST /api/tenants/register` — create tenant, return plaintext API key once
    * `GET /api/tenants/me` — return current tenant profile
  """

  use SLEWeb, :controller

  alias SLE.Tenants

  action_fallback SLEWeb.FallbackController

  @doc """
  POST /api/tenants/register

  Creates a new tenant. Returns the tenant ID, name, and plaintext API key.
  The API key is shown only once — it is stored hashed.

  Guarded by `SELF_REGISTRATION_ENABLED` config flag.
  """
  @spec register(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def register(conn, params) do
    case Tenants.register(params) do
      {:ok, tenant, api_key} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: tenant.id,
          name: tenant.name,
          apiKey: api_key
        })

      {:error, :registration_disabled} ->
        {:error, :forbidden}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  GET /api/tenants/me

  Returns the authenticated tenant's profile.
  """
  @spec me(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def me(conn, _params) do
    tenant = conn.assigns.current_tenant

    json(conn, %{
      id: tenant.id,
      name: tenant.name,
      apiKeyPrefix: tenant.api_key_prefix,
      isActive: tenant.is_active,
      createdAt: tenant.inserted_at
    })
  end
end
