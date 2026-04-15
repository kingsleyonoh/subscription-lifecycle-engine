defmodule SLE.DunningTest do
  @moduledoc false

  use SLE.DataCase, async: true

  import SLE.Factory

  alias SLE.Dunning

  setup do
    tenant = insert(:tenant)
    customer = insert(:customer, tenant_id: tenant.id)
    plan = insert(:plan, tenant_id: tenant.id, amount_cents: 2999)

    sub =
      insert(:subscription,
        tenant_id: tenant.id,
        customer_id: customer.id,
        plan_id: plan.id,
        status: "past_due"
      )

    invoice =
      insert(:invoice,
        tenant_id: tenant.id,
        subscription_id: sub.id,
        customer_id: customer.id,
        status: "open",
        amount_due_cents: 2999
      )

    {:ok, tenant: tenant, customer: customer, plan: plan, subscription: sub, invoice: invoice}
  end

  describe "create/2" do
    test "creates a dunning attempt with pending status", ctx do
      attrs = %{
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        customer_id: ctx.customer.id,
        notification_payload: %{"template" => "dunning.payment_failed.first"}
      }

      assert {:ok, dunning} = Dunning.create(ctx.tenant.id, attrs)
      assert dunning.status == "pending"
      assert dunning.attempt_number == 0
      assert dunning.max_attempts == 4
      assert dunning.escalation_channel == "email"
      assert dunning.tenant_id == ctx.tenant.id
    end

    test "returns error for duplicate invoice_id", ctx do
      attrs = %{
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        customer_id: ctx.customer.id,
        notification_payload: %{}
      }

      assert {:ok, _} = Dunning.create(ctx.tenant.id, attrs)
      assert {:error, changeset} = Dunning.create(ctx.tenant.id, attrs)
      assert %{invoice_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "returns error for missing required fields", ctx do
      assert {:error, changeset} = Dunning.create(ctx.tenant.id, %{})
      refute changeset.valid?
    end
  end

  describe "advance/3" do
    test "transitions from pending to retrying", ctx do
      dunning = insert_dunning(ctx)

      error_info = %{"message" => "Card declined", "code" => "card_declined"}
      assert {:ok, advanced} = Dunning.advance(ctx.tenant.id, dunning.id, error_info)

      assert advanced.status == "retrying"
      assert advanced.attempt_number == 1
      assert advanced.escalation_channel == "email"
      assert length(advanced.error_log) == 1
      assert hd(advanced.error_log)["message"] == "Card declined"
      assert advanced.last_attempted_at != nil
      assert advanced.next_attempt_at != nil
    end

    test "transitions from retrying to retrying (increment attempt)", ctx do
      dunning = insert_dunning(ctx, status: "retrying", attempt_number: 1)

      error_info = %{"message" => "Insufficient funds"}
      assert {:ok, advanced} = Dunning.advance(ctx.tenant.id, dunning.id, error_info)

      assert advanced.status == "retrying"
      assert advanced.attempt_number == 2
      assert advanced.escalation_channel == "email"
    end

    test "escalation channel progresses to telegram at attempt 3", ctx do
      dunning = insert_dunning(ctx, status: "retrying", attempt_number: 2)

      error_info = %{"message" => "Card declined"}
      assert {:ok, advanced} = Dunning.advance(ctx.tenant.id, dunning.id, error_info)

      assert advanced.attempt_number == 3
      assert advanced.escalation_channel == "telegram"
    end

    test "escalation channel progresses to email_telegram at final attempt", ctx do
      dunning =
        insert_dunning(ctx, status: "retrying", attempt_number: 3, max_attempts: 4)

      error_info = %{"message" => "Card declined"}
      assert {:ok, advanced} = Dunning.advance(ctx.tenant.id, dunning.id, error_info)

      assert advanced.attempt_number == 4
      assert advanced.escalation_channel == "email_telegram"
    end

    test "appends to error_log", ctx do
      dunning =
        insert_dunning(ctx,
          status: "retrying",
          attempt_number: 1,
          error_log: [%{"message" => "First error"}]
        )

      error_info = %{"message" => "Second error"}
      assert {:ok, advanced} = Dunning.advance(ctx.tenant.id, dunning.id, error_info)

      assert length(advanced.error_log) == 2
      assert Enum.at(advanced.error_log, 0)["message"] == "First error"
      assert Enum.at(advanced.error_log, 1)["message"] == "Second error"
    end

    test "returns error for terminal status (recovered)", ctx do
      dunning = insert_dunning(ctx, status: "recovered")

      assert {:error, :terminal_status} =
               Dunning.advance(ctx.tenant.id, dunning.id, %{"msg" => "err"})
    end

    test "returns error for terminal status (canceled)", ctx do
      dunning = insert_dunning(ctx, status: "canceled")

      assert {:error, :terminal_status} =
               Dunning.advance(ctx.tenant.id, dunning.id, %{"msg" => "err"})
    end

    test "returns not_found for wrong tenant", ctx do
      other_tenant = insert(:tenant)

      dunning = insert_dunning(ctx)

      assert {:error, :not_found} =
               Dunning.advance(other_tenant.id, dunning.id, %{"msg" => "err"})
    end
  end

  describe "recover/3" do
    test "marks retrying attempt as recovered", ctx do
      dunning = insert_dunning(ctx, status: "retrying", attempt_number: 2)

      assert {:ok, recovered} = Dunning.recover(ctx.tenant.id, dunning.id, 2999)
      assert recovered.status == "recovered"
      assert recovered.recovery_amount == 2999
    end

    test "marks pending attempt as recovered", ctx do
      dunning = insert_dunning(ctx, status: "pending")

      assert {:ok, recovered} = Dunning.recover(ctx.tenant.id, dunning.id, 1500)
      assert recovered.status == "recovered"
      assert recovered.recovery_amount == 1500
    end

    test "returns error for already recovered", ctx do
      dunning = insert_dunning(ctx, status: "recovered")

      assert {:error, :terminal_status} = Dunning.recover(ctx.tenant.id, dunning.id, 2999)
    end

    test "returns not_found for wrong tenant", ctx do
      other_tenant = insert(:tenant)
      dunning = insert_dunning(ctx)

      assert {:error, :not_found} = Dunning.recover(other_tenant.id, dunning.id, 2999)
    end
  end

  describe "exhaust/2" do
    test "marks retrying attempt as exhausted", ctx do
      dunning = insert_dunning(ctx, status: "retrying", attempt_number: 4)

      assert {:ok, exhausted} = Dunning.exhaust(ctx.tenant.id, dunning.id)
      assert exhausted.status == "exhausted"
    end

    test "returns error for already exhausted", ctx do
      dunning = insert_dunning(ctx, status: "exhausted")

      assert {:error, :invalid_transition} = Dunning.exhaust(ctx.tenant.id, dunning.id)
    end

    test "returns error for recovered", ctx do
      dunning = insert_dunning(ctx, status: "recovered")

      assert {:error, :invalid_transition} = Dunning.exhaust(ctx.tenant.id, dunning.id)
    end
  end

  describe "cancel/2" do
    test "marks exhausted attempt as canceled", ctx do
      dunning = insert_dunning(ctx, status: "exhausted")

      assert {:ok, canceled} = Dunning.cancel(ctx.tenant.id, dunning.id)
      assert canceled.status == "canceled"
    end

    test "returns error for non-exhausted status", ctx do
      dunning = insert_dunning(ctx, status: "retrying")

      assert {:error, :invalid_transition} = Dunning.cancel(ctx.tenant.id, dunning.id)
    end

    test "returns error for already canceled", ctx do
      dunning = insert_dunning(ctx, status: "canceled")

      assert {:error, :invalid_transition} = Dunning.cancel(ctx.tenant.id, dunning.id)
    end
  end

  describe "list/2" do
    test "returns dunning attempts for tenant", ctx do
      insert_dunning(ctx)

      result = Dunning.list(ctx.tenant.id)
      assert length(result.data) == 1
    end

    test "filters by status", ctx do
      insert_dunning(ctx, status: "pending")

      other_invoice =
        insert(:invoice,
          tenant_id: ctx.tenant.id,
          subscription_id: ctx.subscription.id,
          customer_id: ctx.customer.id
        )

      insert_dunning(ctx, status: "retrying", invoice_id: other_invoice.id)

      result = Dunning.list(ctx.tenant.id, status: "pending")
      assert length(result.data) == 1
      assert hd(result.data).status == "pending"
    end

    test "filters by subscription_id", ctx do
      insert_dunning(ctx)

      other_customer = insert(:customer, tenant_id: ctx.tenant.id)
      other_sub = insert(:subscription, tenant_id: ctx.tenant.id, customer_id: other_customer.id)

      other_invoice =
        insert(:invoice,
          tenant_id: ctx.tenant.id,
          subscription_id: other_sub.id,
          customer_id: other_customer.id
        )

      insert(:dunning_attempt,
        tenant_id: ctx.tenant.id,
        subscription_id: other_sub.id,
        invoice_id: other_invoice.id,
        customer_id: other_customer.id,
        status: "pending",
        notification_payload: %{}
      )

      result = Dunning.list(ctx.tenant.id, subscription_id: ctx.subscription.id)
      assert length(result.data) == 1
    end

    test "supports cursor pagination", ctx do
      # Create 5 dunning attempts with different invoices
      for _i <- 1..5 do
        inv =
          insert(:invoice,
            tenant_id: ctx.tenant.id,
            subscription_id: ctx.subscription.id,
            customer_id: ctx.customer.id
          )

        insert(:dunning_attempt,
          tenant_id: ctx.tenant.id,
          subscription_id: ctx.subscription.id,
          invoice_id: inv.id,
          customer_id: ctx.customer.id,
          status: "pending",
          notification_payload: %{}
        )
      end

      result1 = Dunning.list(ctx.tenant.id, limit: 3)
      assert length(result1.data) == 3
      assert result1.meta.has_more == true

      result2 = Dunning.list(ctx.tenant.id, limit: 3, cursor: result1.meta.cursor)
      assert length(result2.data) == 2
      assert result2.meta.has_more == false
    end

    test "does not return dunning from other tenants", ctx do
      insert_dunning(ctx)

      other_tenant = insert(:tenant)
      result = Dunning.list(other_tenant.id)
      assert result.data == []
    end
  end

  describe "get/2" do
    test "returns dunning attempt with preloads", ctx do
      dunning = insert_dunning(ctx)

      assert {:ok, found} = Dunning.get(ctx.tenant.id, dunning.id)
      assert found.id == dunning.id
      assert found.tenant.id == ctx.tenant.id
      assert found.subscription.id == ctx.subscription.id
      assert found.invoice.id == ctx.invoice.id
    end

    test "returns not_found for non-existent ID", ctx do
      assert {:error, :not_found} = Dunning.get(ctx.tenant.id, Ecto.UUID.generate())
    end

    test "returns not_found for wrong tenant", ctx do
      dunning = insert_dunning(ctx)
      other_tenant = insert(:tenant)

      assert {:error, :not_found} = Dunning.get(other_tenant.id, dunning.id)
    end
  end

  # --- Helper ---

  defp insert_dunning(ctx, overrides \\ []) do
    attrs =
      Keyword.merge(
        [
          tenant_id: ctx.tenant.id,
          subscription_id: ctx.subscription.id,
          invoice_id: ctx.invoice.id,
          customer_id: ctx.customer.id,
          status: "pending",
          notification_payload: %{"template" => "dunning.payment_failed.first"}
        ],
        overrides
      )

    insert(:dunning_attempt, attrs)
  end
end
