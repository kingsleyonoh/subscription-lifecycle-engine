defmodule SLE.Subscriptions.SubscriptionEventTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Subscriptions.SubscriptionEvent

  import SLE.Factory

  describe "changeset/2 with valid data" do
    test "creates a valid changeset with all required fields" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_test_123",
        event_type: "customer.subscription.created",
        payload: %{"id" => "sub_123"},
        idempotency_key: "#{tenant.id}:evt_test_123"
      }

      changeset = SubscriptionEvent.changeset(%SubscriptionEvent{}, attrs)
      assert changeset.valid?
    end

    test "persists subscription event to database" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      attrs = %{
        tenant_id: tenant.id,
        subscription_id: sub.id,
        stripe_event_id: "evt_persist_1",
        event_type: "customer.subscription.updated",
        previous_status: "trialing",
        new_status: "active",
        payload: %{"id" => "sub_123", "status" => "active"},
        idempotency_key: "#{tenant.id}:evt_persist_1"
      }

      changeset = SubscriptionEvent.changeset(%SubscriptionEvent{}, attrs)
      assert {:ok, event} = Repo.insert(changeset)
      assert event.id != nil
      assert event.tenant_id == tenant.id
      assert event.subscription_id == sub.id
      assert event.stripe_event_id == "evt_persist_1"
      assert event.event_type == "customer.subscription.updated"
      assert event.previous_status == "trialing"
      assert event.new_status == "active"
      assert event.processed_at == nil
      assert event.processing_error == nil
    end
  end

  describe "changeset/2 required field validation" do
    test "requires tenant_id" do
      attrs = %{
        stripe_event_id: "evt_x",
        event_type: "invoice.paid",
        payload: %{},
        idempotency_key: "key"
      }

      changeset = SubscriptionEvent.changeset(%SubscriptionEvent{}, attrs)
      assert %{tenant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires stripe_event_id" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        event_type: "invoice.paid",
        payload: %{},
        idempotency_key: "key"
      }

      changeset = SubscriptionEvent.changeset(%SubscriptionEvent{}, attrs)
      assert %{stripe_event_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires event_type" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_x",
        payload: %{},
        idempotency_key: "key"
      }

      changeset = SubscriptionEvent.changeset(%SubscriptionEvent{}, attrs)
      assert %{event_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires payload" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_x",
        event_type: "invoice.paid",
        idempotency_key: "key",
        payload: nil
      }

      changeset = SubscriptionEvent.changeset(%SubscriptionEvent{}, attrs)
      assert %{payload: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires idempotency_key" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_x",
        event_type: "invoice.paid",
        payload: %{}
      }

      changeset = SubscriptionEvent.changeset(%SubscriptionEvent{}, attrs)
      assert %{idempotency_key: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 optional fields" do
    test "subscription_id is optional (nullable)" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_no_sub",
        event_type: "customer.subscription.created",
        payload: %{"id" => "sub_new"},
        idempotency_key: "#{tenant.id}:evt_no_sub"
      }

      {:ok, event} =
        %SubscriptionEvent{}
        |> SubscriptionEvent.changeset(attrs)
        |> Repo.insert()

      assert event.subscription_id == nil
    end

    test "previous_status and new_status are optional" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_no_status",
        event_type: "invoice.created",
        payload: %{},
        idempotency_key: "#{tenant.id}:evt_no_status"
      }

      {:ok, event} =
        %SubscriptionEvent{}
        |> SubscriptionEvent.changeset(attrs)
        |> Repo.insert()

      assert event.previous_status == nil
      assert event.new_status == nil
    end

    test "processed_at is optional" do
      tenant = insert(:tenant)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_processed",
        event_type: "invoice.paid",
        payload: %{},
        idempotency_key: "#{tenant.id}:evt_processed",
        processed_at: now
      }

      {:ok, event} =
        %SubscriptionEvent{}
        |> SubscriptionEvent.changeset(attrs)
        |> Repo.insert()

      assert event.processed_at == now
    end
  end

  describe "changeset/2 uniqueness constraints" do
    test "enforces unique (tenant_id, idempotency_key)" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_dup",
        event_type: "invoice.paid",
        payload: %{},
        idempotency_key: "#{tenant.id}:evt_dup"
      }

      {:ok, _} = %SubscriptionEvent{} |> SubscriptionEvent.changeset(attrs) |> Repo.insert()

      assert {:error, changeset} =
               %SubscriptionEvent{} |> SubscriptionEvent.changeset(attrs) |> Repo.insert()

      assert %{idempotency_key: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same idempotency_key for different tenants" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      base = %{
        stripe_event_id: "evt_shared",
        event_type: "invoice.paid",
        payload: %{}
      }

      {:ok, _} =
        %SubscriptionEvent{}
        |> SubscriptionEvent.changeset(
          Map.merge(base, %{
            tenant_id: tenant_a.id,
            idempotency_key: "#{tenant_a.id}:evt_shared"
          })
        )
        |> Repo.insert()

      assert {:ok, _} =
               %SubscriptionEvent{}
               |> SubscriptionEvent.changeset(
                 Map.merge(base, %{
                   tenant_id: tenant_b.id,
                   idempotency_key: "#{tenant_b.id}:evt_shared"
                 })
               )
               |> Repo.insert()
    end
  end

  describe "FK cascade behavior" do
    test "deleting tenant cascades to subscription events" do
      tenant = insert(:tenant)
      _event = insert(:subscription_event, tenant_id: tenant.id)

      Repo.delete!(tenant)

      remaining =
        SubscriptionEvent
        |> where([e], e.tenant_id == ^tenant.id)
        |> Repo.all()

      assert remaining == []
    end

    test "deleting subscription nilifies subscription_id" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)
      event = insert(:subscription_event, tenant_id: tenant.id, subscription_id: sub.id)

      Repo.delete!(sub)
      reloaded = Repo.get!(SubscriptionEvent, event.id)
      assert reloaded.subscription_id == nil
    end
  end

  describe "defaults" do
    test "payload defaults to empty map" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_default_payload",
        event_type: "invoice.paid",
        payload: %{},
        idempotency_key: "#{tenant.id}:evt_default_payload"
      }

      {:ok, event} =
        %SubscriptionEvent{}
        |> SubscriptionEvent.changeset(attrs)
        |> Repo.insert()

      assert event.payload == %{}
    end
  end

  describe "timestamps" do
    test "sets inserted_at and updated_at on insert" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        stripe_event_id: "evt_ts",
        event_type: "invoice.paid",
        payload: %{},
        idempotency_key: "#{tenant.id}:evt_ts"
      }

      {:ok, event} =
        %SubscriptionEvent{}
        |> SubscriptionEvent.changeset(attrs)
        |> Repo.insert()

      assert event.inserted_at != nil
      assert event.updated_at != nil
    end
  end
end
