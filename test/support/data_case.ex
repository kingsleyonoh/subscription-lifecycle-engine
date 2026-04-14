defmodule SLE.DataCase do
  @moduledoc """
  Test case for data layer tests.

  Sets up the Ecto sandbox for database isolation.
  Use `async: true` for concurrent tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias SLE.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import SLE.DataCase
    end
  end

  setup tags do
    SLE.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(SLE.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Transforms changeset errors into a map of messages.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
