defmodule SLE.Ecosystem.WorkflowEngineTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias SLE.Ecosystem.WorkflowEngine

  describe "execute_workflow/2" do
    test "posts to workflow engine URL with correct path and headers" do
      bypass = Bypass.open()

      Application.put_env(:sle, :workflow_engine_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :workflow_engine_api_key, "test_wf_key_456")

      on_exit(fn ->
        Application.delete_env(:sle, :workflow_engine_url)
        Application.delete_env(:sle, :workflow_engine_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/workflows/wf_123/execute", fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test_wf_key_456"]
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["trigger_data"] == %{"amount" => 1000}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{execution_id: "exec_789"}))
      end)

      assert {:ok, "exec_789"} = WorkflowEngine.execute_workflow("wf_123", %{amount: 1000})
    end

    test "returns error when server responds with 500" do
      bypass = Bypass.open()

      Application.put_env(:sle, :workflow_engine_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :workflow_engine_api_key, "test_wf_key_456")

      on_exit(fn ->
        Application.delete_env(:sle, :workflow_engine_url)
        Application.delete_env(:sle, :workflow_engine_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/workflows/wf_123/execute", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{error: "internal error"}))
      end)

      assert {:error, _reason} = WorkflowEngine.execute_workflow("wf_123", %{amount: 1000})
    end

    test "returns error when connection fails" do
      Application.put_env(:sle, :workflow_engine_url, "http://localhost:1")
      Application.put_env(:sle, :workflow_engine_api_key, "test_wf_key_456")

      on_exit(fn ->
        Application.delete_env(:sle, :workflow_engine_url)
        Application.delete_env(:sle, :workflow_engine_api_key)
      end)

      assert {:error, _reason} = WorkflowEngine.execute_workflow("wf_123", %{amount: 1000})
    end

    test "sends trigger_data wrapped in body" do
      bypass = Bypass.open()

      Application.put_env(:sle, :workflow_engine_url, "http://localhost:#{bypass.port}")
      Application.put_env(:sle, :workflow_engine_api_key, "key")

      on_exit(fn ->
        Application.delete_env(:sle, :workflow_engine_url)
        Application.delete_env(:sle, :workflow_engine_api_key)
      end)

      Bypass.expect_once(bypass, "POST", "/api/workflows/wf_abc/execute", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert Map.has_key?(decoded, "trigger_data")
        assert decoded["trigger_data"]["foo"] == "bar"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{execution_id: "exec_001"}))
      end)

      assert {:ok, "exec_001"} = WorkflowEngine.execute_workflow("wf_abc", %{foo: "bar"})
    end
  end
end
