defmodule SLE.Tenants.TenantTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Tenants.Tenant

  @valid_attrs %{
    name: "Test Tenant",
    api_key_hash: "abc123def456abc123def456abc123def456abc123def456abc123def456abcd",
    api_key_prefix: "sle_live_abc123"
  }

  describe "changeset/2 with valid data" do
    test "creates a valid changeset with all required fields" do
      changeset = Tenant.changeset(%Tenant{}, @valid_attrs)
      assert changeset.valid?
    end

    test "persists tenant to database" do
      changeset = Tenant.changeset(%Tenant{}, @valid_attrs)
      assert {:ok, tenant} = Repo.insert(changeset)
      assert tenant.id != nil
      assert tenant.name == "Test Tenant"
      assert tenant.api_key_hash == @valid_attrs.api_key_hash
      assert tenant.api_key_prefix == "sle_live_abc123"
    end
  end

  describe "changeset/2 required field validation" do
    test "requires name" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = Tenant.changeset(%Tenant{}, attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires api_key_hash" do
      attrs = Map.delete(@valid_attrs, :api_key_hash)
      changeset = Tenant.changeset(%Tenant{}, attrs)
      assert %{api_key_hash: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires api_key_prefix" do
      attrs = Map.delete(@valid_attrs, :api_key_prefix)
      changeset = Tenant.changeset(%Tenant{}, attrs)
      assert %{api_key_prefix: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 defaults" do
    test "stripe_config defaults to empty map" do
      changeset = Tenant.changeset(%Tenant{}, @valid_attrs)
      {:ok, tenant} = Repo.insert(changeset)
      assert tenant.stripe_config == %{}
    end

    test "is_active defaults to true" do
      changeset = Tenant.changeset(%Tenant{}, @valid_attrs)
      {:ok, tenant} = Repo.insert(changeset)
      assert tenant.is_active == true
    end
  end

  describe "changeset/2 uniqueness constraints" do
    test "api_key_hash must be unique" do
      changeset1 = Tenant.changeset(%Tenant{}, @valid_attrs)
      {:ok, _tenant1} = Repo.insert(changeset1)

      attrs2 = Map.put(@valid_attrs, :name, "Second Tenant")
      changeset2 = Tenant.changeset(%Tenant{}, attrs2)
      assert {:error, changeset} = Repo.insert(changeset2)
      assert %{api_key_hash: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 with stripe_config" do
    test "accepts custom stripe_config" do
      attrs = Map.put(@valid_attrs, :stripe_config, %{"publishable_key" => "pk_test_123"})
      changeset = Tenant.changeset(%Tenant{}, attrs)
      {:ok, tenant} = Repo.insert(changeset)
      assert tenant.stripe_config == %{"publishable_key" => "pk_test_123"}
    end
  end

  describe "timestamps" do
    test "sets inserted_at and updated_at on insert" do
      changeset = Tenant.changeset(%Tenant{}, @valid_attrs)
      {:ok, tenant} = Repo.insert(changeset)
      assert tenant.inserted_at != nil
      assert tenant.updated_at != nil
    end
  end
end
