defmodule SLE.Jobs.EventProcessorJobTest do
  use SLE.DataCase, async: true

  @moduledoc false

  use Oban.Testing, repo: SLE.Repo

  alias SLE.Jobs.EventProcessorJob
  alias SLE.Subscriptions.SubscriptionEvent

  import SLE.Factory

  describe "perform/1" do
    test "processes a subscription event and sets processed_at" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "customer.subscription.created",
          processed_at: nil
        )

      assert :ok =
               EventProcessorJob.perform(%Oban.Job{
                 args: %{"subscription_event_id" => event.id}
               })

      reloaded = Repo.get!(SubscriptionEvent, event.id)
      assert reloaded.processed_at != nil
    end

    test "processes an invoice event and sets processed_at" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "invoice.paid",
          processed_at: nil
        )

      assert :ok =
               EventProcessorJob.perform(%Oban.Job{
                 args: %{"subscription_event_id" => event.id}
               })

      reloaded = Repo.get!(SubscriptionEvent, event.id)
      assert reloaded.processed_at != nil
    end

    test "processes a payment_intent event and sets processed_at" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "payment_intent.succeeded",
          processed_at: nil
        )

      assert :ok =
               EventProcessorJob.perform(%Oban.Job{
                 args: %{"subscription_event_id" => event.id}
               })

      reloaded = Repo.get!(SubscriptionEvent, event.id)
      assert reloaded.processed_at != nil
    end

    test "marks unknown event types as processed" do
      tenant = insert(:tenant)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "checkout.session.completed",
          processed_at: nil
        )

      assert :ok =
               EventProcessorJob.perform(%Oban.Job{
                 args: %{"subscription_event_id" => event.id}
               })

      reloaded = Repo.get!(SubscriptionEvent, event.id)
      assert reloaded.processed_at != nil
    end

    test "returns error when event not found" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :event_not_found} =
               EventProcessorJob.perform(%Oban.Job{
                 args: %{"subscription_event_id" => fake_id}
               })
    end

    test "skips already-processed events" do
      tenant = insert(:tenant)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      event =
        insert(:subscription_event,
          tenant_id: tenant.id,
          event_type: "customer.subscription.created",
          processed_at: now
        )

      assert :ok =
               EventProcessorJob.perform(%Oban.Job{
                 args: %{"subscription_event_id" => event.id}
               })

      reloaded = Repo.get!(SubscriptionEvent, event.id)
      assert reloaded.processed_at == now
    end
  end
end
