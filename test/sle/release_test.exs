defmodule SLE.ReleaseTest do
  @moduledoc """
  Tests for the release module used in Docker container startup.
  """

  use ExUnit.Case, async: true

  test "module defines migrate/0 function" do
    Code.ensure_loaded!(SLE.Release)
    assert function_exported?(SLE.Release, :migrate, 0)
  end

  test "module defines rollback/2 function" do
    Code.ensure_loaded!(SLE.Release)
    assert function_exported?(SLE.Release, :rollback, 2)
  end
end
