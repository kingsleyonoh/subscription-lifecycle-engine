defmodule SLEWeb.Router do
  use SLEWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug SLEWeb.Plugs.Auth
    plug SLEWeb.Plugs.TenantScope
  end

  # Public routes (no auth required)
  scope "/api", SLEWeb do
    pipe_through :api

    post "/tenants/register", TenantController, :register
    get "/health", HealthController, :index
    get "/health/db", HealthController, :db
    get "/health/ready", HealthController, :ready
  end

  # Authenticated routes (require X-API-Key)
  scope "/api", SLEWeb do
    pipe_through [:api, :authenticated]

    get "/tenants/me", TenantController, :me
  end
end
