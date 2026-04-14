defmodule SLE.Ecosystem.NotificationHub do
  @moduledoc """
  HTTP client for the Event-Driven Notification Hub.

  Implements `SLE.Ecosystem.NotificationHubBehaviour`.

  Fire-and-forget: catches all exceptions, logs errors, never raises.
  Uses 5-second timeout.
  """

  @behaviour SLE.Ecosystem.NotificationHubBehaviour

  require Logger

  @timeout 5_000

  @impl true
  @spec send_event(String.t(), map()) :: :ok | {:error, term()}
  def send_event(event_type, payload) do
    url = Application.get_env(:sle, :notification_hub_url)
    api_key = Application.get_env(:sle, :notification_hub_api_key)
    event_id = "#{event_type}-#{Ecto.UUID.generate()}"

    body =
      Jason.encode!(%{
        event_type: event_type,
        event_id: event_id,
        payload: payload
      })

    case Req.post("#{url}/api/events",
           body: body,
           headers: [
             {"content-type", "application/json"},
             {"x-api-key", api_key}
           ],
           receive_timeout: @timeout,
           connect_options: [timeout: @timeout],
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("NotificationHub: sent #{event_type} (#{event_id})")
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("NotificationHub: #{event_type} returned #{status}")
        :ok

      {:error, reason} ->
        Logger.warning("NotificationHub: #{event_type} failed: #{inspect(reason)}")
        :ok
    end
  rescue
    error ->
      Logger.error("NotificationHub: unexpected error: #{inspect(error)}")
      :ok
  end
end
