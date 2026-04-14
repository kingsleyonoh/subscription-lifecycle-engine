defmodule SLE.Ecosystem.ReconEngineTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias SLE.Ecosystem.ReconEngine

  describe "sync_transactions/1" do
    test "posts to recon engine URL with correct path and headers" do
      bypass = Bypass.open()

      Application.put_env(:sle, :recon_engine_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :recon_engine_api_key, "test_recon_key_789")

      on_exit(fn ->
        Application.delete_env(:sle, :recon_engine_url)
        Application.delete_env(:sle, :recon_engine_api_key)
      end)

      transactions = [
        %{
          reference: "in_123",
          amount: 4999,
          currency: "usd",
          type: "credit",
          source: "stripe",
          date: "2026-04-14T10:30:00Z",
          metadata: %{stripe_charge_id: "ch_xxx"}
        }
      ]

      Bypass.expect_once(bypass, "POST", "/api/v1/transactions/ingest/batch", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test_recon_key_789"]
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["transactions"] == [%{
          "reference" => "in_123",
          "amount" => 4999,
          "currency" => "usd",
          "type" => "credit",
          "source" => "stripe",
          "date" => "2026-04-14T10:30:00Z",
          "metadata" => %{"stripe_charge_id" => "ch_xxx"}
        }]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{synced: 1}))
      end)

      assert {:ok, %{"synced" => 1}} = ReconEngine.sync_transactions(transactions)
    end

    test "returns error when server responds with 500" do
      bypass = Bypass.open()

      Application.put_env(:sle, :recon_engine_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :recon_engine_api_key, "test_recon_key_789")

      on_exit(fn ->
        Application.delete_env(:sle, :recon_engine_url)
        Application.delete_env(:sle, :recon_engine_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/v1/transactions/ingest/batch", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{error: "internal error"}))
      end)

      assert {:error, {:http_error, 500}} =
               ReconEngine.sync_transactions([%{reference: "in_123"}])
    end

    test "returns error when connection fails (graceful degradation)" do
      Application.put_env(:sle, :recon_engine_url, "http://localhost:1")
      Application.put_env(:sle, :recon_engine_api_key, "test_recon_key_789")

      on_exit(fn ->
        Application.delete_env(:sle, :recon_engine_url)
        Application.delete_env(:sle, :recon_engine_api_key)
      end)

      assert {:error, _reason} = ReconEngine.sync_transactions([%{reference: "in_123"}])
    end

    test "sends transactions wrapped in body" do
      bypass = Bypass.open()

      Application.put_env(:sle, :recon_engine_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :recon_engine_api_key, "key")

      on_exit(fn ->
        Application.delete_env(:sle, :recon_engine_url)
        Application.delete_env(:sle, :recon_engine_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/v1/transactions/ingest/batch", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert Map.has_key?(decoded, "transactions")
        assert is_list(decoded["transactions"])
        assert length(decoded["transactions"]) == 2

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{synced: 2}))
      end)

      txns = [%{reference: "in_1"}, %{reference: "in_2"}]
      assert {:ok, %{"synced" => 2}} = ReconEngine.sync_transactions(txns)
    end

    test "returns error when server responds with 401 unauthorized" do
      bypass = Bypass.open()

      Application.put_env(:sle, :recon_engine_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :recon_engine_api_key, "bad_key")

      on_exit(fn ->
        Application.delete_env(:sle, :recon_engine_url)
        Application.delete_env(:sle, :recon_engine_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/v1/transactions/ingest/batch", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(%{error: "unauthorized"}))
      end)

      assert {:error, {:http_error, 401}} =
               ReconEngine.sync_transactions([%{reference: "in_123"}])
    end
  end
end
