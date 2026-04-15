defmodule SLE.Pagination do
  @moduledoc """
  Cursor-based pagination utility for Ecto queries.

  Uses Base64-encoded UUIDs as cursors. Works with any Ecto query
  that has a UUID primary key (`id` field).

  ## Usage

      query = from(s in Subscription, where: s.tenant_id == ^tid, order_by: [asc: s.id])
      {results, meta} = Pagination.paginate(query, cursor: cursor, limit: 25)
      # meta = %{cursor: "base64...", has_more: true}

  ## Limits

    - Default: 25 records per page
    - Maximum: 100 records per page
  """

  import Ecto.Query

  alias SLE.Repo

  @default_limit 25
  @max_limit 100

  @type meta :: %{cursor: String.t() | nil, has_more: boolean()}

  @doc """
  Paginate an Ecto query using cursor-based pagination.

  ## Options

    - `:cursor` — Base64-encoded UUID of the last record from previous page
    - `:limit` — number of records per page (default 25, max 100)

  Returns `{results, meta}` where meta contains `:cursor` and `:has_more`.
  """
  @spec paginate(Ecto.Queryable.t(), keyword()) :: {[struct()], meta()}
  def paginate(query, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> clamp_limit()
    cursor = Keyword.get(opts, :cursor)

    query
    |> apply_cursor(cursor)
    |> limit(^(limit + 1))
    |> Repo.all()
    |> build_response(limit)
  end

  @doc """
  Encode a UUID into a cursor string.
  """
  @spec encode_cursor(String.t()) :: String.t()
  def encode_cursor(uuid) do
    Base.url_encode64(uuid, padding: false)
  end

  @doc """
  Decode a cursor string back to a UUID.

  Returns `{:ok, uuid}` or `:error`.
  """
  @spec decode_cursor(String.t()) :: {:ok, String.t()} | :error
  def decode_cursor(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         {:ok, _uuid} <- Ecto.UUID.cast(decoded) do
      {:ok, decoded}
    else
      _ -> :error
    end
  end

  # --- Private Helpers ---

  defp clamp_limit(limit) when is_integer(limit) and limit > @max_limit, do: @max_limit
  defp clamp_limit(limit) when is_integer(limit) and limit < 1, do: @default_limit
  defp clamp_limit(limit) when is_integer(limit), do: limit
  defp clamp_limit(_), do: @default_limit

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, cursor) do
    case decode_cursor(cursor) do
      {:ok, uuid} -> where(query, [r], r.id > ^uuid)
      :error -> where(query, [r], false)
    end
  end

  defp build_response(records, limit) do
    has_more = length(records) > limit
    results = Enum.take(records, limit)

    cursor =
      case List.last(results) do
        nil -> nil
        last -> encode_cursor(last.id)
      end

    meta = %{cursor: cursor, has_more: has_more}
    {results, meta}
  end
end
