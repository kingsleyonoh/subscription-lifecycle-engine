defmodule SLE.Webhooks.IdempotencyTest do
  use SLE.DataCase, async: true

  @moduledoc false

  alias SLE.Webhooks.Idempotency

  import SLE.Factory

  describe "check/2" do
    test "returns {:ok, :new} when event does not exist" do
      tenant = insert(:tenant)
      assert {:ok, :new} = Idempotency.check(tenant.id, "evt_new_123")
    end

    test "returns {:ok, :duplicate, event} when event exists and is processed" do
      tenant = insert(:tenant)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          stripe_event_id: "evt_dup_123",
          idempotency_key: "#{tenant.id}:evt_dup_123",
          processed_at: now
        )

      assert {:ok, :duplicate, found} = Idempotency.check(tenant.id, "evt_dup_123")
      assert found.id == event.id
      assert found.processed_at == now
    end

    test "returns {:ok, :processing, event} when event exists but not yet processed" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          stripe_event_id: "evt_proc_123",
          idempotency_key: "#{tenant.id}:evt_proc_123",
          processed_at: nil
        )

      assert {:ok, :processing, found} = Idempotency.check(tenant.id, "evt_proc_123")
      assert found.id == event.id
      assert found.processed_at == nil
    end

    test "tenant isolation: does not find events from another tenant" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      _event =
        insert(:subscription_event,
          tenant_id: tenant_a.id,
          stripe_event_id: "evt_iso_123",
          idempotency_key: "#{tenant_a.id}:evt_iso_123",
          processed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:ok, :new} = Idempotency.check(tenant_b.id, "evt_iso_123")
    end
  end
end
