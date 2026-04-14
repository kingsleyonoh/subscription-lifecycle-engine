defmodule SLE.Ecosystem.NotificationHubTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias SLE.Ecosystem.NotificationHub

  describe "send_event/2" do
    test "posts to notification hub URL with correct headers and payload" do
      bypass = Bypass.open()

      Application.put_env(:sle, :notification_hub_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :notification_hub_api_key, "test_hub_key_123")

      on_exit(fn ->
        Application.delete_env(:sle, :notification_hub_url)
        Application.delete_env(:sle, :notification_hub_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/events", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test_hub_key_123"]
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["event_type"] == "subscription.trial_ending"
        assert is_binary(decoded["event_id"])
        assert String.starts_with?(decoded["event_id"], "subscription.trial_ending-")
        assert decoded["payload"] == %{"email" => "user@example.com"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "accepted"}))
      end)

      assert :ok = NotificationHub.send_event("subscription.trial_ending", %{email: "user@example.com"})
    end

    test "returns :ok even when the request fails (fire-and-forget)" do
      bypass = Bypass.open()

      Application.put_env(:sle, :notification_hub_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :notification_hub_api_key, "test_hub_key_123")

      on_exit(fn ->
        Application.delete_env(:sle, :notification_hub_url)
        Application.delete_env(:sle, :notification_hub_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/events", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{error: "internal server error"}))
      end)

      assert :ok = NotificationHub.send_event("subscription.trial_ending", %{email: "user@example.com"})
    end

    test "returns :ok when connection is refused (fire-and-forget)" do
      Application.put_env(:sle, :notification_hub_url, "http://localhost:1")
      Application.put_env(:sle, :notification_hub_api_key, "test_hub_key_123")

      on_exit(fn ->
        Application.delete_env(:sle, :notification_hub_url)
        Application.delete_env(:sle, :notification_hub_api_key)
      end)

      # Should never raise, even with an unreachable server
      assert :ok = NotificationHub.send_event("subscription.trial_ending", %{email: "user@example.com"})
    end

    test "generates unique event_id for each call" do
      bypass = Bypass.open()

      Application.put_env(:sle, :notification_hub_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :notification_hub_api_key, "key")

      on_exit(fn ->
        Application.delete_env(:sle, :notification_hub_url)
        Application.delete_env(:sle, :notification_hub_api_key)
      end)

      test_pid = self()

      Bypass.expect(bypass, "POST", "/api/events", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:event_id, decoded["event_id"]})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      NotificationHub.send_event("test.event", %{})
      NotificationHub.send_event("test.event", %{})

      assert_receive {:event_id, id1}
      assert_receive {:event_id, id2}
      assert id1 != id2
    end
  end
end
