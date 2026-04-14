defmodule SLE.Metrics.ArpuCalculatorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias SLE.Metrics.ArpuCalculator

  describe "compute/2" do
    test "returns 0 when active_count is 0" do
      assert ArpuCalculator.compute(10_000, 0) == 0
    end

    test "returns 0 when mrr_cents is 0" do
      assert ArpuCalculator.compute(0, 10) == 0
    end

    test "computes integer division of mrr_cents / active_count" do
      # 10000 / 50 = 200
      assert ArpuCalculator.compute(10_000, 50) == 200
    end

    test "rounds down with integer division" do
      # 10000 / 3 = 3333 (integer division)
      assert ArpuCalculator.compute(10_000, 3) == 3333
    end

    test "handles single subscriber" do
      assert ArpuCalculator.compute(5000, 1) == 5000
    end

    test "returns 0 when both inputs are 0" do
      assert ArpuCalculator.compute(0, 0) == 0
    end
  end
end
