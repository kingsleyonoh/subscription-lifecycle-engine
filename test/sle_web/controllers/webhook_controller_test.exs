defmodule SLEWeb.WebhookControllerTest do
  @moduledoc """
  Tests for the webhook handler endpoint:
  - POST /api/webhook-handler
  """

  use SLEWeb.ConnCase, async: true

  import SLE.Factory

  setup do
    SLEWeb.Plugs.RateLimit.reset_all()

    unique = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    api_key = "sle_live_" <> unique
    hash = :crypto.hash(:sha256, api_key) |> Base.encode16(case: :lower)
    prefix = String.slice(api_key, 0, 13)

    tenant = insert(:tenant, api_key_hash: hash, api_key_prefix: prefix)

    {:ok, tenant: tenant, api_key: api_key}
  end

  describe "POST /api/webhook-handler" do
    test "accepts valid webhook event and returns 200", %{conn: conn, api_key: api_key} do
      payload = %{
        "id" => "evt_test_001",
        "type" => "customer.subscription.created",
        "data" => %{
          "object" => %{
            "id" => "sub_test_001",
            "status" => "trialing"
          }
        }
      }

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhook-handler", payload)

      assert %{"received" => true} = json_response(conn, 200)
    end

    test "returns duplicate status for already-processed event", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert(:subscription_event,
        tenant_id: tenant.id,
        stripe_event_id: "evt_dup_001",
        idempotency_key: "#{tenant.id}:evt_dup_001",
        processed_at: now
      )

      payload = %{
        "id" => "evt_dup_001",
        "type" => "customer.subscription.created",
        "data" => %{"object" => %{}}
      }

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhook-handler", payload)

      resp = json_response(conn, 200)
      assert resp["received"] == true
      assert resp["status"] == "duplicate"
    end

    test "returns processing status for in-progress event", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      insert(:subscription_event,
        tenant_id: tenant.id,
        stripe_event_id: "evt_proc_001",
        idempotency_key: "#{tenant.id}:evt_proc_001",
        processed_at: nil
      )

      payload = %{
        "id" => "evt_proc_001",
        "type" => "customer.subscription.updated",
        "data" => %{"object" => %{}}
      }

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhook-handler", payload)

      resp = json_response(conn, 200)
      assert resp["received"] == true
      assert resp["status"] == "processing"
    end

    test "inserts subscription_event record on new event", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      payload = %{
        "id" => "evt_insert_001",
        "type" => "invoice.paid",
        "data" => %{"object" => %{"id" => "in_123"}}
      }

      conn
      |> put_req_header("x-api-key", api_key)
      |> put_req_header("content-type", "application/json")
      |> post("/api/webhook-handler", payload)

      event =
        SLE.Repo.get_by(SLE.Subscriptions.SubscriptionEvent,
          tenant_id: tenant.id,
          stripe_event_id: "evt_insert_001"
        )

      assert event != nil
      assert event.event_type == "invoice.paid"
      assert event.idempotency_key == "#{tenant.id}:evt_insert_001"
    end

    test "enqueues and processes EventProcessorJob for new events (inline mode)", %{
      conn: conn,
      api_key: api_key,
      tenant: tenant
    } do
      payload = %{
        "id" => "evt_job_001",
        "type" => "customer.subscription.updated",
        "data" => %{"object" => %{"id" => "sub_123"}}
      }

      conn
      |> put_req_header("x-api-key", api_key)
      |> put_req_header("content-type", "application/json")
      |> post("/api/webhook-handler", payload)

      # With Oban testing: :inline, the job runs synchronously.
      # Verify the event was created and processed.
      event =
        SLE.Repo.get_by(SLE.Subscriptions.SubscriptionEvent,
          tenant_id: tenant.id,
          stripe_event_id: "evt_job_001"
        )

      assert event != nil
      assert event.processed_at != nil
    end

    test "returns 401 without API key", %{conn: conn} do
      payload = %{
        "id" => "evt_no_auth",
        "type" => "invoice.paid",
        "data" => %{"object" => %{}}
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhook-handler", payload)

      assert json_response(conn, 401)
    end

    test "handles missing id in payload gracefully", %{conn: conn, api_key: api_key} do
      payload = %{
        "type" => "invoice.paid",
        "data" => %{"object" => %{}}
      }

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhook-handler", payload)

      assert json_response(conn, 400)
    end

    test "handles missing type in payload gracefully", %{conn: conn, api_key: api_key} do
      payload = %{
        "id" => "evt_no_type",
        "data" => %{"object" => %{}}
      }

      conn =
        conn
        |> put_req_header("x-api-key", api_key)
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhook-handler", payload)

      assert json_response(conn, 400)
    end
  end
end
