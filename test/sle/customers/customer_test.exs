defmodule SLE.Customers.CustomerTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Customers.Customer

  import SLE.Factory

  describe "changeset/2 with valid data" do
    test "creates a valid changeset with all required fields" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_customer_id: "cus_test_123",
        email: "test@example.com",
        name: "Jane Doe"
      }

      changeset = Customer.changeset(%Customer{}, attrs)
      assert changeset.valid?
    end

    test "persists customer to database" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_customer_id: "cus_test_456",
        email: "persist@example.com",
        name: "John Doe"
      }

      changeset = Customer.changeset(%Customer{}, attrs)
      assert {:ok, customer} = Repo.insert(changeset)
      assert customer.id != nil
      assert customer.tenant_id == tenant.id
      assert customer.stripe_customer_id == "cus_test_456"
      assert customer.email == "persist@example.com"
      assert customer.name == "John Doe"
    end
  end

  describe "changeset/2 required field validation" do
    test "requires tenant_id" do
      attrs = %{stripe_customer_id: "cus_test_req"}
      changeset = Customer.changeset(%Customer{}, attrs)
      assert %{tenant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires stripe_customer_id" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id}
      changeset = Customer.changeset(%Customer{}, attrs)
      assert %{stripe_customer_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 defaults" do
    test "metadata defaults to empty map" do
      tenant = insert(:tenant)

      attrs = %{tenant_id: tenant.id, stripe_customer_id: "cus_defaults"}
      changeset = Customer.changeset(%Customer{}, attrs)
      {:ok, customer} = Repo.insert(changeset)
      assert customer.metadata == %{}
    end
  end

  describe "changeset/2 uniqueness constraints" do
    test "enforces unique (tenant_id, stripe_customer_id)" do
      tenant = insert(:tenant)

      attrs = %{tenant_id: tenant.id, stripe_customer_id: "cus_unique_test"}
      {:ok, _} = %Customer{} |> Customer.changeset(attrs) |> Repo.insert()

      attrs2 = %{
        tenant_id: tenant.id,
        stripe_customer_id: "cus_unique_test",
        email: "other@test.com"
      }

      assert {:error, changeset} = %Customer{} |> Customer.changeset(attrs2) |> Repo.insert()
      assert %{stripe_customer_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same stripe_customer_id for different tenants" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      attrs_a = %{tenant_id: tenant_a.id, stripe_customer_id: "cus_shared"}
      {:ok, _} = %Customer{} |> Customer.changeset(attrs_a) |> Repo.insert()

      attrs_b = %{tenant_id: tenant_b.id, stripe_customer_id: "cus_shared"}
      assert {:ok, _} = %Customer{} |> Customer.changeset(attrs_b) |> Repo.insert()
    end
  end

  describe "changeset/2 optional fields" do
    test "email and name are optional" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, stripe_customer_id: "cus_no_optionals"}
      changeset = Customer.changeset(%Customer{}, attrs)
      assert changeset.valid?
      {:ok, customer} = Repo.insert(changeset)
      assert customer.email == nil
      assert customer.name == nil
    end

    test "accepts custom metadata" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_customer_id: "cus_meta",
        metadata: %{"source" => "import"}
      }

      {:ok, customer} = %Customer{} |> Customer.changeset(attrs) |> Repo.insert()
      assert customer.metadata == %{"source" => "import"}
    end
  end

  describe "timestamps" do
    test "sets inserted_at and updated_at on insert" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, stripe_customer_id: "cus_ts"}
      {:ok, customer} = %Customer{} |> Customer.changeset(attrs) |> Repo.insert()
      assert customer.inserted_at != nil
      assert customer.updated_at != nil
    end
  end
end
