defmodule SLEWeb.ChangesetJSON do
  @moduledoc """
  Transforms Ecto changeset errors into the standard PRD error format.

  Output format:
      %{
        error: %{
          code: "VALIDATION_ERROR",
          message: "Validation failed",
          details: [%{field: "name", message: "can't be blank"}, ...]
        }
      }
  """

  @doc """
  Renders changeset validation errors in the standard error format.
  """
  @spec error(%{changeset: Ecto.Changeset.t()}) :: map()
  def error(%{changeset: changeset}) do
    details =
      changeset
      |> Ecto.Changeset.traverse_errors(&translate_error/1)
      |> Enum.flat_map(fn {field, messages} ->
        Enum.map(messages, fn message ->
          %{field: to_string(field), message: message}
        end)
      end)

    %{
      error: %{
        code: "VALIDATION_ERROR",
        message: "Validation failed",
        details: details
      }
    }
  end

  defp translate_error({message, opts}) do
    Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
