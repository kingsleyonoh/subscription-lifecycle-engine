defmodule SLE.Subscriptions.SubscriptionTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Subscriptions.Subscription

  import SLE.Factory

  @valid_statuses ~w(trialing active past_due paused canceled unpaid incomplete incomplete_expired)

  describe "changeset/2 with valid data" do
    test "creates a valid changeset with all required fields" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_test_123",
        status: "active"
      }

      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert changeset.valid?
    end

    test "persists subscription to database" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      plan = insert(:plan, tenant_id: tenant.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        stripe_subscription_id: "sub_persist_1",
        status: "trialing",
        current_period_start: now,
        current_period_end: DateTime.add(now, 30, :day),
        trial_start: now,
        trial_end: DateTime.add(now, 14, :day)
      }

      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert {:ok, sub} = Repo.insert(changeset)
      assert sub.id != nil
      assert sub.tenant_id == tenant.id
      assert sub.customer_id == customer.id
      assert sub.plan_id == plan.id
      assert sub.stripe_subscription_id == "sub_persist_1"
      assert sub.status == "trialing"
      assert sub.trial_start != nil
      assert sub.trial_end != nil
    end
  end

  describe "changeset/2 required field validation" do
    test "requires tenant_id" do
      attrs = %{
        stripe_subscription_id: "sub_x",
        status: "active",
        customer_id: Ecto.UUID.generate()
      }

      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert %{tenant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires customer_id" do
      tenant = insert(:tenant)
      attrs = %{tenant_id: tenant.id, stripe_subscription_id: "sub_x", status: "active"}
      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert %{customer_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires stripe_subscription_id" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      attrs = %{tenant_id: tenant.id, customer_id: customer.id, status: "active"}
      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert %{stripe_subscription_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires status" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_x"
      }

      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert %{status: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 status validation" do
    test "accepts all valid statuses" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      for status <- @valid_statuses do
        attrs = %{
          tenant_id: tenant.id,
          customer_id: customer.id,
          stripe_subscription_id: "sub_status_#{status}",
          status: status
        }

        changeset = Subscription.changeset(%Subscription{}, attrs)
        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "rejects invalid status" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_bad_status",
        status: "expired"
      }

      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert %{status: [_msg]} = errors_on(changeset)
    end
  end

  describe "changeset/2 defaults" do
    test "cancel_at_period_end defaults to false" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_default_cancel",
        status: "active"
      }

      {:ok, sub} = %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert()
      assert sub.cancel_at_period_end == false
    end

    test "trial_ending_notified defaults to false" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_default_notified",
        status: "trialing"
      }

      {:ok, sub} = %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert()
      assert sub.trial_ending_notified == false
    end

    test "metadata defaults to empty map" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_default_meta",
        status: "active"
      }

      {:ok, sub} = %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert()
      assert sub.metadata == %{}
    end
  end

  describe "changeset/2 uniqueness constraints" do
    test "enforces unique (tenant_id, stripe_subscription_id)" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_unique",
        status: "active"
      }

      {:ok, _} = %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert()

      customer2 = insert(:customer, tenant_id: tenant.id)
      attrs2 = %{attrs | customer_id: customer2.id}

      assert {:error, changeset} =
               %Subscription{} |> Subscription.changeset(attrs2) |> Repo.insert()

      assert %{stripe_subscription_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same stripe_subscription_id for different tenants" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      customer_a = insert(:customer, tenant_id: tenant_a.id)
      customer_b = insert(:customer, tenant_id: tenant_b.id)

      base = %{stripe_subscription_id: "sub_shared", status: "active"}

      {:ok, _} =
        %Subscription{}
        |> Subscription.changeset(
          Map.merge(base, %{tenant_id: tenant_a.id, customer_id: customer_a.id})
        )
        |> Repo.insert()

      assert {:ok, _} =
               %Subscription{}
               |> Subscription.changeset(
                 Map.merge(base, %{tenant_id: tenant_b.id, customer_id: customer_b.id})
               )
               |> Repo.insert()
    end
  end

  describe "changeset/2 optional fields" do
    test "plan_id is optional (nullable)" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_no_plan",
        status: "incomplete"
      }

      {:ok, sub} = %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert()
      assert sub.plan_id == nil
    end

    test "accepts custom metadata" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_meta_custom",
        status: "active",
        metadata: %{"source" => "migration"}
      }

      {:ok, sub} = %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert()
      assert sub.metadata == %{"source" => "migration"}
    end
  end

  describe "FK cascade behavior" do
    test "deleting tenant cascades to subscriptions" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      _sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      Repo.delete!(tenant)

      assert Repo.all(Subscription) == []
    end
  end

  describe "timestamps" do
    test "sets inserted_at and updated_at on insert" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      attrs = %{
        tenant_id: tenant.id,
        customer_id: customer.id,
        stripe_subscription_id: "sub_ts",
        status: "active"
      }

      {:ok, sub} = %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert()
      assert sub.inserted_at != nil
      assert sub.updated_at != nil
    end
  end
end
