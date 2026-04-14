defmodule SLEWeb.FallbackController do
  @moduledoc """
  Translates controller action results into standard error responses.

  Used as the action_fallback for controllers. Handles common error
  tuples and renders them in the PRD-defined error format.

  ## Handled patterns

    - `{:error, :not_found}` -> 404
    - `{:error, :unauthorized}` -> 401
    - `{:error, :forbidden}` -> 403
    - `{:error, :conflict}` -> 409
    - `{:error, :rate_limited}` -> 429
    - `{:error, %Ecto.Changeset{}}` -> 400 with field details
  """

  use SLEWeb, :controller

  alias SLEWeb.ChangesetJSON

  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SLEWeb.ErrorJSON)
    |> json(ChangesetJSON.error(%{changeset: changeset}))
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SLEWeb.ErrorJSON)
    |> json(%{error: %{code: "NOT_FOUND", message: "Resource not found"}})
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: SLEWeb.ErrorJSON)
    |> json(%{error: %{code: "UNAUTHORIZED", message: "Invalid or missing API key"}})
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: SLEWeb.ErrorJSON)
    |> json(%{error: %{code: "FORBIDDEN", message: "Access denied"}})
  end

  def call(conn, {:error, :conflict}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SLEWeb.ErrorJSON)
    |> json(%{error: %{code: "CONFLICT", message: "Resource conflict"}})
  end

  def call(conn, {:error, :rate_limited}) do
    conn
    |> put_status(:too_many_requests)
    |> put_view(json: SLEWeb.ErrorJSON)
    |> json(%{error: %{code: "RATE_LIMITED", message: "Too many requests"}})
  end
end
