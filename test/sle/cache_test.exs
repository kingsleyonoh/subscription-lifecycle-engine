defmodule SLE.CacheTest do
  use ExUnit.Case, async: true

  @moduledoc false

  describe "get/2" do
    test "returns nil for missing keys" do
      assert SLE.Cache.get(:tenant, "nonexistent_key_#{:rand.uniform(999_999)}") == nil
    end

    test "returns the cached value" do
      key = "cache_test_get_#{:rand.uniform(999_999)}"
      SLE.Cache.put(:tenant, key, %{id: 1, name: "Test"})

      assert SLE.Cache.get(:tenant, key) == %{id: 1, name: "Test"}
    end
  end

  describe "put/4" do
    test "stores and retrieves a value" do
      key = "cache_test_put_#{:rand.uniform(999_999)}"
      assert :ok = SLE.Cache.put(:tenant, key, "hello")
      assert SLE.Cache.get(:tenant, key) == "hello"
    end

    test "overwrites existing values" do
      key = "cache_test_overwrite_#{:rand.uniform(999_999)}"
      SLE.Cache.put(:tenant, key, "first")
      SLE.Cache.put(:tenant, key, "second")

      assert SLE.Cache.get(:tenant, key) == "second"
    end
  end

  describe "delete/2" do
    test "removes a cached entry" do
      key = "cache_test_delete_#{:rand.uniform(999_999)}"
      SLE.Cache.put(:tenant, key, "to_delete")
      assert SLE.Cache.get(:tenant, key) == "to_delete"

      assert :ok = SLE.Cache.delete(:tenant, key)
      assert SLE.Cache.get(:tenant, key) == nil
    end

    test "returns :ok for missing keys" do
      assert :ok = SLE.Cache.delete(:tenant, "never_existed_#{:rand.uniform(999_999)}")
    end
  end

  describe "clear/0" do
    test "removes all entries" do
      k1 = "cache_test_clear_1_#{:rand.uniform(999_999)}"
      k2 = "cache_test_clear_2_#{:rand.uniform(999_999)}"
      SLE.Cache.put(:tenant, k1, "one")
      SLE.Cache.put(:config, k2, "two")

      assert :ok = SLE.Cache.clear()

      assert SLE.Cache.get(:tenant, k1) == nil
      assert SLE.Cache.get(:config, k2) == nil
    end
  end

  describe "TTL expiration" do
    test "expired entries return nil" do
      key = "cache_test_ttl_#{:rand.uniform(999_999)}"
      # 1ms TTL — will expire almost immediately
      SLE.Cache.put(:tenant, key, "ephemeral", ttl: 1)
      Process.sleep(10)

      assert SLE.Cache.get(:tenant, key) == nil
    end
  end

  describe "namespace isolation" do
    test "same key in different namespaces are independent" do
      key = "cache_test_ns_#{:rand.uniform(999_999)}"
      SLE.Cache.put(:tenant, key, "tenant_value")
      SLE.Cache.put(:config, key, "config_value")

      assert SLE.Cache.get(:tenant, key) == "tenant_value"
      assert SLE.Cache.get(:config, key) == "config_value"
    end
  end
end
