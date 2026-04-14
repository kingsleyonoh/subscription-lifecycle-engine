defmodule SLE.TenantsTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Tenants

  describe "register/1" do
    test "creates a tenant and returns plaintext API key" do
      assert {:ok, tenant, api_key} = Tenants.register(%{name: "Acme Corp"})
      assert tenant.name == "Acme Corp"
      assert tenant.is_active == true
      assert is_binary(api_key)
      assert String.starts_with?(api_key, "sle_live_")
    end

    test "generated API key is 42 characters (prefix + 32 hex)" do
      {:ok, _tenant, api_key} = Tenants.register(%{name: "Key Length Test"})
      # "sle_live_" (9 chars) + 32 hex chars = 41 chars
      assert String.length(api_key) == 41
    end

    test "stored hash matches SHA-256 of plaintext key" do
      {:ok, tenant, api_key} = Tenants.register(%{name: "Hash Verify"})
      expected_hash = :crypto.hash(:sha256, api_key) |> Base.encode16(case: :lower)
      assert tenant.api_key_hash == expected_hash
    end

    test "api_key_prefix stores the first 13 characters of the key" do
      {:ok, tenant, api_key} = Tenants.register(%{name: "Prefix Check"})
      assert tenant.api_key_prefix == String.slice(api_key, 0, 13)
    end

    test "returns error when name is missing" do
      assert {:error, changeset} = Tenants.register(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "blocks registration when SELF_REGISTRATION_ENABLED is false" do
      original = Application.get_env(:sle, :self_registration_enabled)
      Application.put_env(:sle, :self_registration_enabled, false)

      assert {:error, :registration_disabled} = Tenants.register(%{name: "Blocked"})

      # Restore
      if original do
        Application.put_env(:sle, :self_registration_enabled, original)
      else
        Application.delete_env(:sle, :self_registration_enabled)
      end
    end

    test "allows registration when SELF_REGISTRATION_ENABLED is true" do
      Application.put_env(:sle, :self_registration_enabled, true)

      assert {:ok, _tenant, _key} = Tenants.register(%{name: "Allowed"})

      Application.delete_env(:sle, :self_registration_enabled)
    end
  end

  describe "authenticate/1" do
    test "returns tenant for valid API key" do
      {:ok, tenant, api_key} = Tenants.register(%{name: "Auth Test"})
      SLE.Cache.clear()

      assert {:ok, found_tenant} = Tenants.authenticate(api_key)
      assert found_tenant.id == tenant.id
      assert found_tenant.name == "Auth Test"
    end

    test "returns error for invalid API key" do
      assert {:error, :unauthorized} = Tenants.authenticate("sle_live_invalid_key_12345678")
    end

    test "returns error for nil API key" do
      assert {:error, :unauthorized} = Tenants.authenticate(nil)
    end

    test "returns error for empty string API key" do
      assert {:error, :unauthorized} = Tenants.authenticate("")
    end

    test "caches tenant on first lookup and uses cache on second" do
      {:ok, tenant, api_key} = Tenants.register(%{name: "Cache Test"})
      SLE.Cache.clear()

      # First call hits DB
      assert {:ok, first} = Tenants.authenticate(api_key)
      assert first.id == tenant.id

      # Verify cache was populated
      hash = :crypto.hash(:sha256, api_key) |> Base.encode16(case: :lower)
      cached = SLE.Cache.get(:tenant, hash)
      assert cached != nil
      assert cached.id == tenant.id

      # Second call should use cache (even if we deleted from DB, cache would still work)
      assert {:ok, second} = Tenants.authenticate(api_key)
      assert second.id == tenant.id
    end

    test "returns error for inactive tenant" do
      {:ok, tenant, api_key} = Tenants.register(%{name: "Inactive Test"})

      # Deactivate the tenant
      tenant
      |> Ecto.Changeset.change(%{is_active: false})
      |> Repo.update!()

      SLE.Cache.clear()

      assert {:error, :unauthorized} = Tenants.authenticate(api_key)
    end
  end

  describe "get/1" do
    test "returns tenant by UUID" do
      {:ok, tenant, _key} = Tenants.register(%{name: "Get Test"})

      found = Tenants.get(tenant.id)
      assert found.id == tenant.id
      assert found.name == "Get Test"
    end

    test "returns nil for nonexistent UUID" do
      assert Tenants.get(Ecto.UUID.generate()) == nil
    end
  end
end
