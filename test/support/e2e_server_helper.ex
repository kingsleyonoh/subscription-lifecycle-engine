defmodule SLE.E2E.ServerHelper do
  @moduledoc """
  Helpers for starting and stopping the Phoenix server during E2E tests.

  E2E tests hit a running HTTP server (not in-process ConnTest).
  This module manages server lifecycle for test isolation.
  """

  @default_port 4013
  @health_path "/api/health"
  @max_retries 20
  @retry_delay 250

  @doc """
  Returns the base URL for the running test server.
  """
  def base_url(port \\ @default_port) do
    "http://127.0.0.1:#{port}"
  end

  @doc """
  Waits for the server to be ready by polling the health endpoint.
  Returns `:ok` when ready, or `{:error, :timeout}` after max retries.
  """
  def await_ready(port \\ @default_port, retries \\ @max_retries) do
    url = "#{base_url(port)}#{@health_path}"
    do_await_ready(url, retries)
  end

  defp do_await_ready(_url, 0), do: {:error, :timeout}

  defp do_await_ready(url, retries) do
    case Req.get(url) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      _ ->
        Process.sleep(@retry_delay)
        do_await_ready(url, retries - 1)
    end
  rescue
    _ ->
      Process.sleep(@retry_delay)
      do_await_ready(url, retries - 1)
  end
end
