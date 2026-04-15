defmodule SLEWeb.ErrorJSONTest do
  use SLEWeb.ConnCase, async: true

  @moduledoc false

  describe "render/2 with status templates" do
    test "renders 400 in PRD error format" do
      result = SLEWeb.ErrorJSON.render("400.json", %{})
      assert result.error.code == "BAD_REQUEST"
      assert result.error.message == "Bad request"
    end

    test "renders 401 in PRD error format" do
      result = SLEWeb.ErrorJSON.render("401.json", %{})
      assert result.error.code == "UNAUTHORIZED"
      assert result.error.message == "Invalid or missing API key"
    end

    test "renders 403 in PRD error format" do
      result = SLEWeb.ErrorJSON.render("403.json", %{})
      assert result.error.code == "FORBIDDEN"
      assert result.error.message == "Access denied"
    end

    test "renders 404 in PRD error format" do
      result = SLEWeb.ErrorJSON.render("404.json", %{})
      assert result.error.code == "NOT_FOUND"
      assert result.error.message == "Resource not found"
    end

    test "renders 409 in PRD error format" do
      result = SLEWeb.ErrorJSON.render("409.json", %{})
      assert result.error.code == "CONFLICT"
      assert result.error.message == "Resource conflict"
    end

    test "renders 429 in PRD error format" do
      result = SLEWeb.ErrorJSON.render("429.json", %{})
      assert result.error.code == "RATE_LIMITED"
      assert result.error.message == "Too many requests"
    end

    test "renders 500 in PRD error format" do
      result = SLEWeb.ErrorJSON.render("500.json", %{})
      assert result.error.code == "INTERNAL_ERROR"
      assert result.error.message == "Internal server error"
    end

    test "renders unknown status codes with generic error format" do
      result = SLEWeb.ErrorJSON.render("503.json", %{})
      assert result.error.code == "SERVER_ERROR"
      assert is_binary(result.error.message)
    end
  end
end
