defmodule SLE.Ecosystem.ClientPortalTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias SLE.Ecosystem.ClientPortal

  describe "push_metrics/1" do
    test "posts to client portal URL with correct path and headers" do
      bypass = Bypass.open()

      Application.put_env(:sle, :client_portal_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :client_portal_api_key, "test_portal_key_abc")

      on_exit(fn ->
        Application.delete_env(:sle, :client_portal_url)
        Application.delete_env(:sle, :client_portal_api_key)
      end)

      metrics = %{
        mrr_cents: 100_000,
        arr_cents: 1_200_000,
        active_count: 50,
        churn_rate: 0.038,
        period_start: "2026-04-01",
        period_end: "2026-04-14"
      }

      Bypass.expect_once(bypass, "POST", "/api/integration/metrics", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test_portal_key_abc"]
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["mrr_cents"] == 100_000
        assert decoded["arr_cents"] == 1_200_000
        assert decoded["active_count"] == 50

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "accepted"}))
      end)

      assert :ok = ClientPortal.push_metrics(metrics)
    end

    test "returns error when server responds with 500" do
      bypass = Bypass.open()

      Application.put_env(:sle, :client_portal_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :client_portal_api_key, "test_portal_key_abc")

      on_exit(fn ->
        Application.delete_env(:sle, :client_portal_url)
        Application.delete_env(:sle, :client_portal_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/integration/metrics", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{error: "internal error"}))
      end)

      assert {:error, {:http_error, 500}} = ClientPortal.push_metrics(%{mrr_cents: 100_000})
    end

    test "returns error when connection fails" do
      Application.put_env(:sle, :client_portal_url, "http://localhost:1")
      Application.put_env(:sle, :client_portal_api_key, "test_portal_key_abc")

      on_exit(fn ->
        Application.delete_env(:sle, :client_portal_url)
        Application.delete_env(:sle, :client_portal_api_key)
      end)

      assert {:error, _reason} = ClientPortal.push_metrics(%{mrr_cents: 100_000})
    end

    test "returns error when server responds with 401 unauthorized" do
      bypass = Bypass.open()

      Application.put_env(:sle, :client_portal_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :client_portal_api_key, "bad_key")

      on_exit(fn ->
        Application.delete_env(:sle, :client_portal_url)
        Application.delete_env(:sle, :client_portal_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/integration/metrics", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{error: "unauthorized"}))
      end)

      assert {:error, {:http_error, 401}} = ClientPortal.push_metrics(%{mrr_cents: 100_000})
    end

    test "sends metrics data as JSON body" do
      bypass = Bypass.open()

      Application.put_env(:sle, :client_portal_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :client_portal_api_key, "key")

      on_exit(fn ->
        Application.delete_env(:sle, :client_portal_url)
        Application.delete_env(:sle, :client_portal_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/integration/metrics", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["mrr_cents"] == 50_000
        assert decoded["churn_rate"] == 0.05

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      assert :ok = ClientPortal.push_metrics(%{mrr_cents: 50_000, churn_rate: 0.05})
    end
  end
end
