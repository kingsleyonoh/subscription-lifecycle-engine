defmodule SLE.ApplicationTest do
  @moduledoc false

  use ExUnit.Case, async: true

  describe "prep_stop/1" do
    test "prep_stop returns state for graceful shutdown" do
      # prep_stop/1 should be defined and return the state
      state = %{some: "state"}
      assert ^state = SLE.Application.prep_stop(state)
    end
  end
end
