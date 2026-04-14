defmodule SLE.Billing.PlanTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Billing.Plan

  import SLE.Factory

  describe "changeset/2 with valid data" do
    test "creates a valid changeset with all required fields" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_test_123",
        name: "Pro Monthly",
        amount_cents: 2999,
        currency: "usd",
        interval: "month"
      }

      changeset = Plan.changeset(%Plan{}, attrs)
      assert changeset.valid?
    end

    test "persists plan to database" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_persist",
        name: "Enterprise Yearly",
        amount_cents: 49_900,
        currency: "eur",
        interval: "year"
      }

      changeset = Plan.changeset(%Plan{}, attrs)
      assert {:ok, plan} = Repo.insert(changeset)
      assert plan.id != nil
      assert plan.tenant_id == tenant.id
      assert plan.stripe_price_id == "price_persist"
      assert plan.name == "Enterprise Yearly"
      assert plan.amount_cents == 49_900
      assert plan.currency == "eur"
      assert plan.interval == "year"
    end
  end

  describe "changeset/2 required field validation" do
    test "requires tenant_id" do
      attrs = %{stripe_price_id: "price_x", name: "X", amount_cents: 100, interval: "month"}
      changeset = Plan.changeset(%Plan{}, attrs)
      assert %{tenant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires stripe_price_id" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, name: "X", amount_cents: 100, interval: "month"}
      changeset = Plan.changeset(%Plan{}, attrs)
      assert %{stripe_price_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires name" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_x",
        amount_cents: 100,
        interval: "month"
      }

      changeset = Plan.changeset(%Plan{}, attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires amount_cents" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, stripe_price_id: "price_x", name: "X", interval: "month"}
      changeset = Plan.changeset(%Plan{}, attrs)
      assert %{amount_cents: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires interval" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, stripe_price_id: "price_x", name: "X", amount_cents: 100}
      changeset = Plan.changeset(%Plan{}, attrs)
      assert %{interval: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 interval validation" do
    test "accepts valid intervals" do
      tenant = insert(:tenant)

      for interval <- ~w(month year week) do
        attrs = %{
          tenant_id: tenant.id,
          stripe_price_id: "price_#{interval}",
          name: "Plan #{interval}",
          amount_cents: 1000,
          interval: interval
        }

        changeset = Plan.changeset(%Plan{}, attrs)
        assert changeset.valid?, "Expected #{interval} to be valid"
      end
    end

    test "rejects invalid interval" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_bad",
        name: "Bad Plan",
        amount_cents: 1000,
        interval: "daily"
      }

      changeset = Plan.changeset(%Plan{}, attrs)
      assert %{interval: [_msg]} = errors_on(changeset)
    end
  end

  describe "changeset/2 defaults" do
    test "currency defaults to usd" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_default_cur",
        name: "Default Currency",
        amount_cents: 999,
        interval: "month"
      }

      {:ok, plan} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
      assert plan.currency == "usd"
    end

    test "is_active defaults to true" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_default_active",
        name: "Default Active",
        amount_cents: 999,
        interval: "month"
      }

      {:ok, plan} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
      assert plan.is_active == true
    end

    test "metadata defaults to empty map" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_default_meta",
        name: "Default Meta",
        amount_cents: 999,
        interval: "month"
      }

      {:ok, plan} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
      assert plan.metadata == %{}
    end
  end

  describe "changeset/2 uniqueness constraints" do
    test "enforces unique (tenant_id, stripe_price_id)" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_unique",
        name: "First Plan",
        amount_cents: 1000,
        interval: "month"
      }

      {:ok, _} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()

      attrs2 = %{attrs | name: "Second Plan"}
      assert {:error, changeset} = %Plan{} |> Plan.changeset(attrs2) |> Repo.insert()
      assert %{stripe_price_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same stripe_price_id for different tenants" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      base = %{
        stripe_price_id: "price_shared",
        name: "Plan",
        amount_cents: 1000,
        interval: "month"
      }

      {:ok, _} =
        %Plan{} |> Plan.changeset(Map.put(base, :tenant_id, tenant_a.id)) |> Repo.insert()

      assert {:ok, _} =
               %Plan{} |> Plan.changeset(Map.put(base, :tenant_id, tenant_b.id)) |> Repo.insert()
    end
  end

  describe "changeset/2 optional fields" do
    test "accepts custom metadata" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_meta_custom",
        name: "Meta Plan",
        amount_cents: 500,
        interval: "week",
        metadata: %{"features" => ["a", "b"]}
      }

      {:ok, plan} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
      assert plan.metadata == %{"features" => ["a", "b"]}
    end

    test "accepts is_active false" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_inactive",
        name: "Inactive Plan",
        amount_cents: 500,
        interval: "month",
        is_active: false
      }

      {:ok, plan} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
      assert plan.is_active == false
    end
  end

  describe "timestamps" do
    test "sets inserted_at and updated_at on insert" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_price_id: "price_ts",
        name: "Timestamp Plan",
        amount_cents: 100,
        interval: "month"
      }

      {:ok, plan} = %Plan{} |> Plan.changeset(attrs) |> Repo.insert()
      assert plan.inserted_at != nil
      assert plan.updated_at != nil
    end
  end
end
