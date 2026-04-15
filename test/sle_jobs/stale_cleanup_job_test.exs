defmodule SLE.Jobs.StaleCleanupJobTest do
  @moduledoc false

  use SLE.DataCase, async: false
  use Oban.Testing, repo: SLE.Repo

  import SLE.Factory

  alias SLE.Jobs.StaleCleanupJob
  alias SLE.Subscriptions.SubscriptionEvent

  describe "perform/1" do
    test "prunes payload of processed events older than 90 days" do
      tenant = insert(:tenant)

      old_event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          payload: %{"id" => "sub_old", "status" => "active"},
          processed_at:
            DateTime.utc_now() |> DateTime.add(-91, :day) |> DateTime.truncate(:second)
        )

      assert :ok = StaleCleanupJob.perform(%Oban.Job{args: %{}})

      updated = Repo.get!(SubscriptionEvent, old_event.id)
      assert updated.payload == %{}
    end

    test "does not prune events newer than 90 days" do
      tenant = insert(:tenant)

      recent_event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          payload: %{"id" => "sub_recent", "status" => "active"},
          processed_at:
            DateTime.utc_now() |> DateTime.add(-89, :day) |> DateTime.truncate(:second)
        )

      assert :ok = StaleCleanupJob.perform(%Oban.Job{args: %{}})

      unchanged = Repo.get!(SubscriptionEvent, recent_event.id)
      assert unchanged.payload == %{"id" => "sub_recent", "status" => "active"}
    end

    test "does not prune unprocessed events even if old" do
      tenant = insert(:tenant)

      unprocessed =
        insert(:subscription_event,
          tenant_id: tenant.id,
          payload: %{"id" => "sub_unprocessed"},
          processed_at: nil,
          inserted_at:
            DateTime.utc_now() |> DateTime.add(-100, :day) |> DateTime.truncate(:second)
        )

      assert :ok = StaleCleanupJob.perform(%Oban.Job{args: %{}})

      unchanged = Repo.get!(SubscriptionEvent, unprocessed.id)
      assert unchanged.payload == %{"id" => "sub_unprocessed"}
    end

    test "does not prune events that already have empty payload" do
      tenant = insert(:tenant)

      already_pruned =
        insert(:subscription_event,
          tenant_id: tenant.id,
          payload: %{},
          processed_at:
            DateTime.utc_now() |> DateTime.add(-100, :day) |> DateTime.truncate(:second)
        )

      assert :ok = StaleCleanupJob.perform(%Oban.Job{args: %{}})

      unchanged = Repo.get!(SubscriptionEvent, already_pruned.id)
      assert unchanged.payload == %{}
    end

    test "prunes multiple old events in one run" do
      tenant = insert(:tenant)

      old1 =
        insert(:subscription_event,
          tenant_id: tenant.id,
          payload: %{"data" => "one"},
          processed_at:
            DateTime.utc_now() |> DateTime.add(-95, :day) |> DateTime.truncate(:second)
        )

      old2 =
        insert(:subscription_event,
          tenant_id: tenant.id,
          payload: %{"data" => "two"},
          processed_at:
            DateTime.utc_now() |> DateTime.add(-120, :day) |> DateTime.truncate(:second)
        )

      assert :ok = StaleCleanupJob.perform(%Oban.Job{args: %{}})

      assert Repo.get!(SubscriptionEvent, old1.id).payload == %{}
      assert Repo.get!(SubscriptionEvent, old2.id).payload == %{}
    end

    test "returns :ok when no events exist" do
      assert :ok = StaleCleanupJob.perform(%Oban.Job{args: %{}})
    end
  end
end
