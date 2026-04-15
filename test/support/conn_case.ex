defmodule SLEWeb.ConnCase do
  @moduledoc """
  Test case for Phoenix controller tests.

  Sets up a connection and the Ecto sandbox for database isolation.
  Use `async: true` for concurrent tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint SLEWeb.Endpoint

      use SLEWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import SLEWeb.ConnCase
    end
  end

  setup tags do
    SLE.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
