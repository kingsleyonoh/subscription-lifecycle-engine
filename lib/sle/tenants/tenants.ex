defmodule SLE.Tenants do
  @moduledoc """
  Context for tenant management.

  Handles tenant registration, API key authentication (with ETS cache),
  and tenant lookup. All other contexts scope queries by tenant_id.
  """

  alias SLE.Cache
  alias SLE.Repo
  alias SLE.Tenants.Tenant

  @api_key_prefix "sle_live_"
  @api_key_hex_length 32
  @cache_namespace :tenant

  # --- Public API ---

  @doc """
  Registers a new tenant.

  Generates a random API key prefixed with `sle_live_`, stores the
  SHA-256 hash, and returns the plaintext key (shown only once).

  Returns `{:ok, tenant, plaintext_api_key}` or `{:error, changeset}`.
  Checks the `SELF_REGISTRATION_ENABLED` config flag first.
  """
  @spec register(map()) ::
          {:ok, Tenant.t(), String.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :registration_disabled}
  def register(attrs) do
    if registration_allowed?() do
      do_register(attrs)
    else
      {:error, :registration_disabled}
    end
  end

  @doc """
  Authenticates a request by API key.

  Computes the SHA-256 hash of the given key and looks it up in the
  ETS cache first, then falls back to a database query. Inactive
  tenants are rejected.

  Returns `{:ok, tenant}` or `{:error, :unauthorized}`.
  """
  @spec authenticate(String.t() | nil) :: {:ok, Tenant.t()} | {:error, :unauthorized}
  def authenticate(nil), do: {:error, :unauthorized}
  def authenticate(""), do: {:error, :unauthorized}

  def authenticate(api_key) when is_binary(api_key) do
    hash = hash_api_key(api_key)

    case Cache.get(@cache_namespace, hash) do
      nil -> authenticate_from_db(hash)
      tenant -> {:ok, tenant}
    end
  end

  @doc """
  Gets a tenant by UUID.

  Returns the tenant struct or `nil` if not found.
  """
  @spec get(Ecto.UUID.t()) :: Tenant.t() | nil
  def get(id) do
    Repo.get(Tenant, id)
  end

  # --- Private Helpers ---

  defp do_register(attrs) do
    api_key = generate_api_key()
    hash = hash_api_key(api_key)
    prefix = String.slice(api_key, 0, 13)

    tenant_attrs =
      attrs
      |> Map.put(:api_key_hash, hash)
      |> Map.put(:api_key_prefix, prefix)

    case %Tenant{} |> Tenant.changeset(tenant_attrs) |> Repo.insert() do
      {:ok, tenant} -> {:ok, tenant, api_key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp authenticate_from_db(hash) do
    case Repo.get_by(Tenant, api_key_hash: hash, is_active: true) do
      nil ->
        {:error, :unauthorized}

      tenant ->
        Cache.put(@cache_namespace, hash, tenant)
        {:ok, tenant}
    end
  end

  defp generate_api_key do
    hex = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    @api_key_prefix <> String.slice(hex, 0, @api_key_hex_length)
  end

  defp hash_api_key(key) do
    :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)
  end

  defp registration_allowed? do
    Application.get_env(:sle, :self_registration_enabled, true)
  end
end
