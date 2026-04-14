defmodule SLE.Cache do
  @moduledoc """
  ETS-based cache for hot-path lookups (tenant resolution).

  Provides get/put/delete with configurable TTL. Started in
  the application supervision tree.

  ## Usage

      SLE.Cache.put(:tenant, api_key_hash, tenant_struct)
      SLE.Cache.get(:tenant, api_key_hash)
      SLE.Cache.delete(:tenant, api_key_hash)
  """

  use GenServer

  @table __MODULE__

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get a cached value. Returns `nil` if not found or expired.
  """
  @spec get(atom(), term()) :: term() | nil
  def get(namespace, key) do
    composite_key = {namespace, key}

    case :ets.lookup(@table, composite_key) do
      [{^composite_key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          value
        else
          :ets.delete(@table, composite_key)
          nil
        end

      [] ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc """
  Put a value in the cache with optional TTL override (ms).
  """
  @spec put(atom(), term(), term(), keyword()) :: :ok
  def put(namespace, key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, default_ttl())
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(@table, {{namespace, key}, value, expires_at})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Delete a cached entry.
  """
  @spec delete(atom(), term()) :: :ok
  def delete(namespace, key) do
    :ets.delete(@table, {namespace, key})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Clear all cached entries.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)
  end

  defp default_ttl do
    Application.get_env(:sle, :cache_ttl, 300_000)
  end
end
