defmodule SLEWeb.ErrorJSON do
  @moduledoc """
  Renders error responses in the standard PRD format:

      {
        "error": {
          "code": "ERROR_CODE",
          "message": "Human-readable description",
          "details": [...]
        }
      }
  """

  @status_map %{
    400 => {"BAD_REQUEST", "Bad request"},
    401 => {"UNAUTHORIZED", "Invalid or missing API key"},
    403 => {"FORBIDDEN", "Access denied"},
    404 => {"NOT_FOUND", "Resource not found"},
    409 => {"CONFLICT", "Resource conflict"},
    429 => {"RATE_LIMITED", "Too many requests"},
    500 => {"INTERNAL_ERROR", "Internal server error"}
  }

  @doc """
  Renders an error response from a Phoenix error template name.

  Template names follow the pattern "STATUS.json" (e.g., "404.json").
  """
  @spec render(String.t(), map()) :: map()
  def render(template, _assigns) do
    status = extract_status(template)

    case Map.get(@status_map, status) do
      {code, message} ->
        %{error: %{code: code, message: message}}

      nil ->
        message = Phoenix.Controller.status_message_from_template(template)
        %{error: %{code: "SERVER_ERROR", message: message}}
    end
  end

  defp extract_status(template) do
    template
    |> String.split(".")
    |> List.first()
    |> String.to_integer()
  rescue
    _ -> 500
  end
end
