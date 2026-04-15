defmodule SLE.Metrics.MetricsSnapshotTest do
  @moduledoc false

  use SLE.DataCase, async: true

  alias SLE.Metrics.MetricsSnapshot

  import SLE.Factory

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-04-14],
        mrr_cents: 50_000,
        arr_cents: 600_000,
        active_count: 25,
        trialing_count: 3,
        churned_count: 2,
        churn_rate: Decimal.new("0.0741"),
        dunning_active: 1,
        dunning_recovered_cents: 0,
        arpu_cents: 2000,
        computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = MetricsSnapshot.changeset(%MetricsSnapshot{}, attrs)
      assert changeset.valid?
    end

    test "requires tenant_id, period_start, period_end, mrr_cents, computed_at" do
      changeset = MetricsSnapshot.changeset(%MetricsSnapshot{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:tenant_id]
      assert errors[:period_start]
      assert errors[:period_end]
      assert errors[:mrr_cents]
      assert errors[:computed_at]
    end

    test "defaults synced_to_portal to false" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-04-14],
        mrr_cents: 50_000,
        computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = MetricsSnapshot.changeset(%MetricsSnapshot{}, attrs)
      assert changeset.valid?

      {:ok, snapshot} = Repo.insert(changeset)
      assert snapshot.synced_to_portal == false
    end

    test "defaults dunning_recovered_cents to 0" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-04-14],
        mrr_cents: 50_000,
        computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:ok, snapshot} = MetricsSnapshot.changeset(%MetricsSnapshot{}, attrs) |> Repo.insert()
      assert snapshot.dunning_recovered_cents == 0
    end

    test "foreign key constraint on tenant_id" do
      attrs = %{
        tenant_id: Ecto.UUID.generate(),
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-04-14],
        mrr_cents: 50_000,
        computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = MetricsSnapshot.changeset(%MetricsSnapshot{}, attrs)

      assert {:error, changeset} = Repo.insert(changeset)
      assert errors_on(changeset)[:tenant_id]
    end

    test "inserts and reads snapshot correctly" do
      tenant = insert(:tenant)

      attrs = %{
        tenant_id: tenant.id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-04-14],
        mrr_cents: 100_000,
        arr_cents: 1_200_000,
        active_count: 50,
        trialing_count: 5,
        churned_count: 3,
        churn_rate: Decimal.new("0.0566"),
        dunning_active: 2,
        dunning_recovered_cents: 5000,
        arpu_cents: 2000,
        synced_to_portal: false,
        computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:ok, snapshot} = MetricsSnapshot.changeset(%MetricsSnapshot{}, attrs) |> Repo.insert()

      reloaded = Repo.get!(MetricsSnapshot, snapshot.id)
      assert reloaded.mrr_cents == 100_000
      assert reloaded.arr_cents == 1_200_000
      assert reloaded.active_count == 50
      assert reloaded.trialing_count == 5
      assert reloaded.churned_count == 3
      assert Decimal.equal?(reloaded.churn_rate, Decimal.new("0.0566"))
      assert reloaded.dunning_active == 2
      assert reloaded.dunning_recovered_cents == 5000
      assert reloaded.arpu_cents == 2000
      assert reloaded.synced_to_portal == false
    end
  end

  describe "factory" do
    test "metrics_snapshot factory creates valid record" do
      tenant = insert(:tenant)
      snapshot = insert(:metrics_snapshot, tenant_id: tenant.id)

      assert snapshot.id != nil
      assert snapshot.tenant_id == tenant.id
      assert snapshot.mrr_cents != nil
      assert snapshot.period_start != nil
      assert snapshot.period_end != nil
    end
  end
end
