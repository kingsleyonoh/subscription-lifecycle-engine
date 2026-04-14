defmodule SLE.Subscriptions.StateMachineTest do
  use ExUnit.Case, async: true

  @moduledoc false

  alias SLE.Subscriptions.StateMachine

  # --- valid_transition?/2 ---

  describe "valid_transition?/2 — valid transitions" do
    test "trialing -> active" do
      assert StateMachine.valid_transition?("trialing", "active")
    end

    test "trialing -> past_due" do
      assert StateMachine.valid_transition?("trialing", "past_due")
    end

    test "trialing -> canceled" do
      assert StateMachine.valid_transition?("trialing", "canceled")
    end

    test "incomplete -> active" do
      assert StateMachine.valid_transition?("incomplete", "active")
    end

    test "incomplete -> incomplete_expired" do
      assert StateMachine.valid_transition?("incomplete", "incomplete_expired")
    end

    test "active -> past_due" do
      assert StateMachine.valid_transition?("active", "past_due")
    end

    test "active -> paused" do
      assert StateMachine.valid_transition?("active", "paused")
    end

    test "active -> canceled" do
      assert StateMachine.valid_transition?("active", "canceled")
    end

    test "past_due -> active" do
      assert StateMachine.valid_transition?("past_due", "active")
    end

    test "past_due -> canceled" do
      assert StateMachine.valid_transition?("past_due", "canceled")
    end

    test "past_due -> unpaid" do
      assert StateMachine.valid_transition?("past_due", "unpaid")
    end

    test "paused -> active" do
      assert StateMachine.valid_transition?("paused", "active")
    end

    test "unpaid -> active" do
      assert StateMachine.valid_transition?("unpaid", "active")
    end
  end

  describe "valid_transition?/2 — invalid transitions" do
    test "active -> trialing is invalid" do
      refute StateMachine.valid_transition?("active", "trialing")
    end

    test "canceled -> active is invalid (terminal)" do
      refute StateMachine.valid_transition?("canceled", "active")
    end

    test "incomplete_expired -> active is invalid (terminal)" do
      refute StateMachine.valid_transition?("incomplete_expired", "active")
    end

    test "paused -> canceled is invalid" do
      refute StateMachine.valid_transition?("paused", "canceled")
    end

    test "trialing -> paused is invalid" do
      refute StateMachine.valid_transition?("trialing", "paused")
    end

    test "unpaid -> canceled is invalid" do
      refute StateMachine.valid_transition?("unpaid", "canceled")
    end

    test "active -> incomplete is invalid" do
      refute StateMachine.valid_transition?("active", "incomplete")
    end

    test "unknown status returns false" do
      refute StateMachine.valid_transition?("unknown", "active")
    end
  end

  # --- transition!/2 ---

  describe "transition!/2" do
    test "returns :ok for valid transition" do
      assert :ok = StateMachine.transition!("trialing", "active")
      assert :ok = StateMachine.transition!("active", "canceled")
      assert :ok = StateMachine.transition!("past_due", "unpaid")
    end

    test "returns error for invalid transition" do
      assert {:error, :invalid_transition} = StateMachine.transition!("canceled", "active")
      assert {:error, :invalid_transition} = StateMachine.transition!("active", "trialing")
    end
  end

  # --- terminal?/1 ---

  describe "terminal?/1" do
    test "canceled is terminal" do
      assert StateMachine.terminal?("canceled")
    end

    test "incomplete_expired is terminal" do
      assert StateMachine.terminal?("incomplete_expired")
    end

    test "active is not terminal" do
      refute StateMachine.terminal?("active")
    end

    test "trialing is not terminal" do
      refute StateMachine.terminal?("trialing")
    end

    test "past_due is not terminal" do
      refute StateMachine.terminal?("past_due")
    end

    test "paused is not terminal" do
      refute StateMachine.terminal?("paused")
    end

    test "unpaid is not terminal" do
      refute StateMachine.terminal?("unpaid")
    end

    test "incomplete is not terminal" do
      refute StateMachine.terminal?("incomplete")
    end
  end

  # --- allowed_transitions/1 ---

  describe "allowed_transitions/1" do
    test "trialing can go to active, past_due, canceled" do
      allowed = StateMachine.allowed_transitions("trialing")
      assert Enum.sort(allowed) == Enum.sort(["active", "past_due", "canceled"])
    end

    test "incomplete can go to active, incomplete_expired" do
      allowed = StateMachine.allowed_transitions("incomplete")
      assert Enum.sort(allowed) == Enum.sort(["active", "incomplete_expired"])
    end

    test "active can go to past_due, paused, canceled" do
      allowed = StateMachine.allowed_transitions("active")
      assert Enum.sort(allowed) == Enum.sort(["past_due", "paused", "canceled"])
    end

    test "past_due can go to active, canceled, unpaid" do
      allowed = StateMachine.allowed_transitions("past_due")
      assert Enum.sort(allowed) == Enum.sort(["active", "canceled", "unpaid"])
    end

    test "paused can only go to active" do
      assert StateMachine.allowed_transitions("paused") == ["active"]
    end

    test "unpaid can only go to active" do
      assert StateMachine.allowed_transitions("unpaid") == ["active"]
    end

    test "canceled has no allowed transitions" do
      assert StateMachine.allowed_transitions("canceled") == []
    end

    test "incomplete_expired has no allowed transitions" do
      assert StateMachine.allowed_transitions("incomplete_expired") == []
    end

    test "unknown status returns empty list" do
      assert StateMachine.allowed_transitions("nonexistent") == []
    end
  end
end
