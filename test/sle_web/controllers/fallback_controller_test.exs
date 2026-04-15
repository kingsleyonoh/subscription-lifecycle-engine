defmodule SLEWeb.FallbackControllerTest do
  use SLEWeb.ConnCase, async: true

  @moduledoc false

  alias SLEWeb.FallbackController

  describe "call/2 with {:error, :not_found}" do
    test "returns 404 with standard error format" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> FallbackController.call({:error, :not_found})

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "NOT_FOUND"
      assert body["error"]["message"] == "Resource not found"
    end
  end

  describe "call/2 with {:error, :unauthorized}" do
    test "returns 401 with standard error format" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> FallbackController.call({:error, :unauthorized})

      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "UNAUTHORIZED"
      assert body["error"]["message"] == "Invalid or missing API key"
    end
  end

  describe "call/2 with {:error, :forbidden}" do
    test "returns 403 with standard error format" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> FallbackController.call({:error, :forbidden})

      assert conn.status == 403
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "FORBIDDEN"
      assert body["error"]["message"] == "Access denied"
    end
  end

  describe "call/2 with {:error, :conflict}" do
    test "returns 409 with standard error format" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> FallbackController.call({:error, :conflict})

      assert conn.status == 409
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "CONFLICT"
      assert body["error"]["message"] == "Resource conflict"
    end
  end

  describe "call/2 with {:error, :rate_limited}" do
    test "returns 429 with standard error format" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> FallbackController.call({:error, :rate_limited})

      assert conn.status == 429
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "RATE_LIMITED"
      assert body["error"]["message"] == "Too many requests"
    end
  end

  describe "call/2 with {:error, %Ecto.Changeset{}}" do
    test "returns 400 with validation error details" do
      changeset =
        {%{}, %{name: :string, email: :string}}
        |> Ecto.Changeset.cast(%{}, [:name, :email])
        |> Ecto.Changeset.validate_required([:name, :email])

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> FallbackController.call({:error, changeset})

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == "VALIDATION_ERROR"
      assert body["error"]["message"] == "Validation failed"
      assert is_list(body["error"]["details"])
      assert length(body["error"]["details"]) == 2

      fields = Enum.map(body["error"]["details"], & &1["field"])
      assert "name" in fields
      assert "email" in fields
    end
  end
end
