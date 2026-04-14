defmodule SLE.SmokeTest do
  use SLE.DataCase, async: true

  @moduledoc false

  describe "database connectivity" do
    test "can execute a query against the local PostgreSQL" do
      result = Ecto.Adapters.SQL.query!(SLE.Repo, "SELECT 1 AS value")
      assert result.num_rows == 1
      assert result.rows == [[1]]
    end

    test "can read the current database name" do
      result = Ecto.Adapters.SQL.query!(SLE.Repo, "SELECT current_database()")
      [[db_name]] = result.rows
      assert String.starts_with?(db_name, "sle_test")
    end
  end
end
