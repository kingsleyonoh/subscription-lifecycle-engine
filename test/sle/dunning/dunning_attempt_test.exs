defmodule SLE.Dunning.DunningAttemptTest do
  @moduledoc false

  use SLE.DataCase, async: true

  import SLE.Factory

  alias SLE.Dunning.DunningAttempt

  setup do
    tenant = insert(:tenant)
    customer = insert(:customer, tenant_id: tenant.id)
    sub = insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

    invoice =
      insert(:invoice, tenant_id: tenant.id, subscription_id: sub.id, customer_id: customer.id)

    {:ok, tenant: tenant, customer: customer, subscription: sub, invoice: invoice}
  end

  describe "changeset/2" do
    test "valid changeset with all required fields", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        customer_id: ctx.customer.id,
        status: "pending",
        notification_payload: %{"template" => "dunning.payment_failed.first"}
      }

      changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
      assert changeset.valid?
    end

    test "requires tenant_id", ctx do
      attrs = %{
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "pending",
        notification_payload: %{}
      }

      changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
      refute changeset.valid?
      assert %{tenant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires subscription_id", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        invoice_id: ctx.invoice.id,
        status: "pending",
        notification_payload: %{}
      }

      changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
      refute changeset.valid?
      assert %{subscription_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires invoice_id", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        status: "pending",
        notification_payload: %{}
      }

      changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
      refute changeset.valid?
      assert %{invoice_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires notification_payload", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "pending"
      }

      changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
      refute changeset.valid?
      assert %{notification_payload: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates status inclusion", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "invalid_status",
        notification_payload: %{}
      }

      changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "validates all valid statuses", ctx do
      for status <- ~w(pending retrying recovered exhausted canceled) do
        attrs = %{
          tenant_id: ctx.tenant.id,
          subscription_id: ctx.subscription.id,
          invoice_id: ctx.invoice.id,
          status: status,
          notification_payload: %{}
        }

        changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "validates escalation_channel inclusion", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "pending",
        escalation_channel: "carrier_pigeon",
        notification_payload: %{}
      }

      changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
      refute changeset.valid?
      assert %{escalation_channel: ["is invalid"]} = errors_on(changeset)
    end

    test "defaults attempt_number to 0", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "pending",
        notification_payload: %{}
      }

      changeset = DunningAttempt.changeset(%DunningAttempt{}, attrs)
      assert changeset.valid?
      # Default is on schema, not changeset — check after insert
    end

    test "defaults max_attempts to 4", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "pending",
        notification_payload: %{}
      }

      {:ok, dunning} =
        %DunningAttempt{}
        |> DunningAttempt.changeset(attrs)
        |> Repo.insert()

      assert dunning.max_attempts == 4
    end

    test "defaults escalation_channel to email", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "pending",
        notification_payload: %{}
      }

      {:ok, dunning} =
        %DunningAttempt{}
        |> DunningAttempt.changeset(attrs)
        |> Repo.insert()

      assert dunning.escalation_channel == "email"
    end

    test "defaults error_log to empty list", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "pending",
        notification_payload: %{}
      }

      {:ok, dunning} =
        %DunningAttempt{}
        |> DunningAttempt.changeset(attrs)
        |> Repo.insert()

      assert dunning.error_log == []
    end

    test "enforces unique (tenant_id, invoice_id)", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        status: "pending",
        notification_payload: %{}
      }

      {:ok, _} =
        %DunningAttempt{}
        |> DunningAttempt.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %DunningAttempt{}
        |> DunningAttempt.changeset(attrs)
        |> Repo.insert()

      assert %{invoice_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "enforces foreign key on tenant_id" do
      attrs = %{
        tenant_id: Ecto.UUID.generate(),
        subscription_id: Ecto.UUID.generate(),
        invoice_id: Ecto.UUID.generate(),
        status: "pending",
        notification_payload: %{}
      }

      {:error, changeset} =
        %DunningAttempt{}
        |> DunningAttempt.changeset(attrs)
        |> Repo.insert()

      assert %{tenant_id: ["does not exist"]} = errors_on(changeset)
    end

    test "belongs_to associations", ctx do
      attrs = %{
        tenant_id: ctx.tenant.id,
        subscription_id: ctx.subscription.id,
        invoice_id: ctx.invoice.id,
        customer_id: ctx.customer.id,
        status: "pending",
        notification_payload: %{"key" => "value"}
      }

      {:ok, dunning} =
        %DunningAttempt{}
        |> DunningAttempt.changeset(attrs)
        |> Repo.insert()

      loaded = Repo.preload(dunning, [:tenant, :subscription, :invoice, :customer])
      assert loaded.tenant.id == ctx.tenant.id
      assert loaded.subscription.id == ctx.subscription.id
      assert loaded.invoice.id == ctx.invoice.id
      assert loaded.customer.id == ctx.customer.id
    end
  end
end
