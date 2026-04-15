defmodule SLE.Subscriptions.StateMachine do
  @moduledoc """
  Subscription state machine with explicit transition map.

  Defines all 15 valid status transitions and 2 terminal states.
  Used by the Subscriptions context to validate transitions before
  persisting status changes.
  """

  @transitions %{
    "trialing" => ["active", "past_due", "canceled"],
    "incomplete" => ["active", "incomplete_expired"],
    "active" => ["past_due", "paused", "canceled"],
    "past_due" => ["active", "canceled", "unpaid"],
    "paused" => ["active"],
    "unpaid" => ["active"],
    "canceled" => [],
    "incomplete_expired" => []
  }

  @terminal_states ~w(canceled incomplete_expired)

  @doc """
  Checks if a transition from one status to another is valid.
  """
  @spec valid_transition?(String.t(), String.t()) :: boolean()
  def valid_transition?(from, to) do
    to in Map.get(@transitions, from, [])
  end

  @doc """
  Attempts a transition. Returns :ok or {:error, :invalid_transition}.
  """
  @spec transition!(String.t(), String.t()) :: :ok | {:error, :invalid_transition}
  def transition!(from, to) do
    if valid_transition?(from, to) do
      :ok
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Returns true if the given status is a terminal state.
  """
  @spec terminal?(String.t()) :: boolean()
  def terminal?(status) do
    status in @terminal_states
  end

  @doc """
  Returns the list of valid target statuses from the given status.
  """
  @spec allowed_transitions(String.t()) :: [String.t()]
  def allowed_transitions(status) do
    Map.get(@transitions, status, [])
  end
end
