defmodule SLE.CustomersTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Customers

  import SLE.Factory

  describe "upsert_from_stripe/2" do
    test "creates a new customer from Stripe data" do
      tenant = insert(:tenant)

      stripe_data = %{
        "id" => "cus_stripe_new",
        "email" => "stripe@example.com",
        "name" => "Stripe User",
        "metadata" => %{"tier" => "pro"}
      }

      assert {:ok, customer} = Customers.upsert_from_stripe(tenant.id, stripe_data)
      assert customer.stripe_customer_id == "cus_stripe_new"
      assert customer.email == "stripe@example.com"
      assert customer.name == "Stripe User"
      assert customer.metadata == %{"tier" => "pro"}
      assert customer.tenant_id == tenant.id
    end

    test "updates existing customer when stripe_customer_id matches" do
      tenant = insert(:tenant)

      # Create initial customer
      stripe_data = %{
        "id" => "cus_stripe_existing",
        "email" => "old@example.com",
        "name" => "Old Name"
      }

      {:ok, original} = Customers.upsert_from_stripe(tenant.id, stripe_data)

      # Upsert with updated data
      updated_stripe_data = %{
        "id" => "cus_stripe_existing",
        "email" => "new@example.com",
        "name" => "New Name",
        "metadata" => %{"updated" => "true"}
      }

      {:ok, updated} = Customers.upsert_from_stripe(tenant.id, updated_stripe_data)
      assert updated.id == original.id
      assert updated.email == "new@example.com"
      assert updated.name == "New Name"
      assert updated.metadata == %{"updated" => "true"}
    end

    test "upsert does not affect different tenant's customer" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      stripe_data = %{"id" => "cus_shared_stripe", "email" => "a@test.com", "name" => "Tenant A"}
      {:ok, customer_a} = Customers.upsert_from_stripe(tenant_a.id, stripe_data)

      stripe_data_b = %{
        "id" => "cus_shared_stripe",
        "email" => "b@test.com",
        "name" => "Tenant B"
      }

      {:ok, customer_b} = Customers.upsert_from_stripe(tenant_b.id, stripe_data_b)

      assert customer_a.id != customer_b.id
      assert customer_a.email == "a@test.com"
      assert customer_b.email == "b@test.com"
    end

    test "handles missing optional fields in stripe data" do
      tenant = insert(:tenant)

      stripe_data = %{"id" => "cus_minimal"}
      {:ok, customer} = Customers.upsert_from_stripe(tenant.id, stripe_data)
      assert customer.stripe_customer_id == "cus_minimal"
      assert customer.email == nil
      assert customer.name == nil
      assert customer.metadata == %{}
    end
  end

  describe "list/2" do
    test "returns customers scoped by tenant_id" do
      tenant = insert(:tenant)
      other_tenant = insert(:tenant)

      insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_list_1")
      insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_list_2")
      insert(:customer, tenant_id: other_tenant.id, stripe_customer_id: "cus_other")

      customers = Customers.list(tenant.id)
      assert length(customers) == 2
      assert Enum.all?(customers, fn c -> c.tenant_id == tenant.id end)
    end

    test "returns empty list when tenant has no customers" do
      tenant = insert(:tenant)
      assert Customers.list(tenant.id) == []
    end

    test "supports limit option" do
      tenant = insert(:tenant)

      for i <- 1..5 do
        insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_limit_#{i}")
      end

      customers = Customers.list(tenant.id, limit: 3)
      assert length(customers) == 3
    end

    test "supports offset option" do
      tenant = insert(:tenant)

      for i <- 1..5 do
        insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_offset_#{i}")
      end

      all_customers = Customers.list(tenant.id)
      offset_customers = Customers.list(tenant.id, offset: 2)
      assert length(offset_customers) == 3
      assert length(all_customers) == 5
    end
  end

  describe "get/2" do
    test "returns customer by id scoped to tenant" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id, stripe_customer_id: "cus_get_1")

      assert {:ok, found} = Customers.get(tenant.id, customer.id)
      assert found.id == customer.id
      assert found.stripe_customer_id == "cus_get_1"
    end

    test "returns error for nonexistent customer" do
      tenant = insert(:tenant)
      assert {:error, :not_found} = Customers.get(tenant.id, Ecto.UUID.generate())
    end

    test "tenant isolation: cannot see other tenant's customer" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant_a.id, stripe_customer_id: "cus_isolated")

      assert {:error, :not_found} = Customers.get(tenant_b.id, customer.id)
    end
  end
end
