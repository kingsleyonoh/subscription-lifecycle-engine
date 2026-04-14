defmodule SLE.Dunning do
  @moduledoc """
  Context for dunning (payment retry) management.

  Handles creation, advancement, recovery, exhaustion, and cancellation
  of dunning attempts. All operations enforce tenant isolation.
  Escalation channel progresses: email (1-2) -> telegram (3-4) -> email_telegram (final).
  """

  import Ecto.Query

  alias SLE.Dunning.DunningAttempt
  alias SLE.Pagination
  alias SLE.Repo

  @terminal_statuses ~w(recovered canceled)

  # --- Public API ---

  @doc """
  Create a new dunning attempt with status 'pending'.
  """
  @spec create(Ecto.UUID.t(), map()) ::
          {:ok, DunningAttempt.t()} | {:error, Ecto.Changeset.t()}
  def create(tenant_id, attrs) do
    attrs =
      attrs
      |> Map.put(:tenant_id, tenant_id)
      |> Map.put(:status, "pending")

    %DunningAttempt{}
    |> DunningAttempt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Advance a dunning attempt: increment attempt, log error, update escalation channel,
  schedule next retry.
  """
  @spec advance(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, DunningAttempt.t()} | {:error, :not_found | :terminal_status}
  def advance(tenant_id, dunning_id, error_info) do
    case get_raw(tenant_id, dunning_id) do
      nil ->
        {:error, :not_found}

      %{status: status} when status in @terminal_statuses ->
        {:error, :terminal_status}

      dunning ->
        do_advance(dunning, error_info)
    end
  end

  @doc """
  Mark a dunning attempt as recovered with the recovery amount.
  """
  @spec recover(Ecto.UUID.t(), Ecto.UUID.t(), integer()) ::
          {:ok, DunningAttempt.t()} | {:error, :not_found | :terminal_status}
  def recover(tenant_id, dunning_id, amount) do
    case get_raw(tenant_id, dunning_id) do
      nil ->
        {:error, :not_found}

      %{status: status} when status in @terminal_statuses ->
        {:error, :terminal_status}

      dunning ->
        dunning
        |> DunningAttempt.changeset(%{
          status: "recovered",
          recovery_amount: amount
        })
        |> Repo.update()
    end
  end

  @doc """
  Mark a dunning attempt as exhausted (max attempts reached).
  Only valid from pending or retrying status.
  """
  @spec exhaust(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, DunningAttempt.t()} | {:error, :not_found | :invalid_transition}
  def exhaust(tenant_id, dunning_id) do
    case get_raw(tenant_id, dunning_id) do
      nil ->
        {:error, :not_found}

      %{status: status} when status in ["pending", "retrying"] ->
        update_status(dunning_id, "exhausted")

      _dunning ->
        {:error, :invalid_transition}
    end
  end

  @doc """
  Mark a dunning attempt as canceled (after subscription canceled).
  Only valid from exhausted status.
  """
  @spec cancel(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, DunningAttempt.t()} | {:error, :not_found | :invalid_transition}
  def cancel(tenant_id, dunning_id) do
    case get_raw(tenant_id, dunning_id) do
      nil ->
        {:error, :not_found}

      %{status: "exhausted"} ->
        update_status(dunning_id, "canceled")

      _dunning ->
        {:error, :invalid_transition}
    end
  end

  @doc """
  List dunning attempts for a tenant with optional filters and cursor pagination.
  """
  @spec list(Ecto.UUID.t(), keyword()) :: %{data: [DunningAttempt.t()], meta: map()}
  def list(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    cursor = Keyword.get(opts, :cursor)

    query =
      DunningAttempt
      |> where([d], d.tenant_id == ^tenant_id)
      |> maybe_filter_status(opts)
      |> maybe_filter_subscription(opts)
      |> order_by([d], asc: d.id)

    {results, meta} = Pagination.paginate(query, cursor: cursor, limit: limit)
    %{data: results, meta: meta}
  end

  @doc """
  Get a dunning attempt by ID, scoped to tenant, with preloads.
  """
  @spec get(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, DunningAttempt.t()} | {:error, :not_found}
  def get(tenant_id, id) do
    DunningAttempt
    |> where([d], d.tenant_id == ^tenant_id and d.id == ^id)
    |> preload([:tenant, :subscription, :invoice, :customer])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      dunning -> {:ok, dunning}
    end
  end

  # --- Private Helpers ---

  defp get_raw(tenant_id, id) do
    DunningAttempt
    |> where([d], d.tenant_id == ^tenant_id and d.id == ^id)
    |> Repo.one()
  end

  defp do_advance(dunning, error_info) do
    new_attempt = dunning.attempt_number + 1
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    channel = escalation_channel(new_attempt, dunning.max_attempts)
    next_at = compute_next_attempt_at(now, new_attempt)
    new_error_log = dunning.error_log ++ [error_info]

    dunning
    |> DunningAttempt.changeset(%{
      status: "retrying",
      attempt_number: new_attempt,
      last_attempted_at: now,
      next_attempt_at: next_at,
      escalation_channel: channel,
      error_log: new_error_log
    })
    |> Repo.update()
  end

  defp update_status(dunning_id, new_status) do
    DunningAttempt
    |> Repo.get!(dunning_id)
    |> DunningAttempt.changeset(%{status: new_status})
    |> Repo.update()
  end

  @doc false
  @spec escalation_channel(integer(), integer()) :: String.t()
  def escalation_channel(attempt, max_attempts) when attempt >= max_attempts do
    "email_telegram"
  end

  def escalation_channel(attempt, _max_attempts) when attempt <= 2, do: "email"
  def escalation_channel(_attempt, _max_attempts), do: "telegram"

  defp compute_next_attempt_at(now, attempt_number) do
    intervals = retry_intervals()
    # attempt_number is 1-based; intervals is 0-indexed
    idx = min(attempt_number - 1, length(intervals) - 1)
    hours = Enum.at(intervals, idx, 24)
    DateTime.add(now, hours * 3600, :second)
  end

  defp retry_intervals do
    case Application.get_env(:sle, :dunning_retry_intervals) do
      intervals when is_binary(intervals) ->
        intervals
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_integer/1)

      _ ->
        [24, 72, 120, 168]
    end
  end

  defp maybe_filter_status(query, opts) do
    case Keyword.get(opts, :status) do
      nil -> query
      status -> where(query, [d], d.status == ^status)
    end
  end

  defp maybe_filter_subscription(query, opts) do
    case Keyword.get(opts, :subscription_id) do
      nil -> query
      sub_id -> where(query, [d], d.subscription_id == ^sub_id)
    end
  end
end
