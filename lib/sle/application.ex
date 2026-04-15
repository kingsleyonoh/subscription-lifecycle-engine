defmodule SLE.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SLEWeb.Telemetry,
      SLE.Repo,
      {DNSCluster, query: Application.get_env(:sle, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SLE.PubSub},
      {Oban, Application.fetch_env!(:sle, Oban)},
      SLE.Cache,
      SLEWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SLE.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Graceful shutdown callback.

  Called before the application stops. Logs shutdown and allows
  in-flight HTTP requests to complete. Req handles connection
  pooling automatically — no explicit pool teardown needed.
  """
  @impl true
  def prep_stop(state) do
    require Logger
    Logger.info("SLE.Application: preparing to stop, draining connections")
    :ok
    state
  end

  @impl true
  def config_change(changed, _new, removed) do
    SLEWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
