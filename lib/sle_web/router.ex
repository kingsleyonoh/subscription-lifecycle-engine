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

    # Webhook handler (500/min rate limit)
    post "/webhook-handler", WebhookController, :handle

    # Plans CRUD
    get "/plans", PlanController, :index
    post "/plans", PlanController, :create
    put "/plans/:id", PlanController, :update

    # Subscriptions
    get "/subscriptions", SubscriptionController, :index
    get "/subscriptions/:id", SubscriptionController, :show
    get "/subscriptions/:id/events", SubscriptionController, :events
    post "/subscriptions/:id/cancel", SubscriptionController, :cancel
    post "/subscriptions/:id/pause", SubscriptionController, :pause
    post "/subscriptions/:id/resume", SubscriptionController, :resume_sub

    # Customers
    get "/customers", CustomerController, :index
    get "/customers/:id", CustomerController, :show

    # Invoices
    get "/invoices", InvoiceController, :index
    get "/invoices/:id", InvoiceController, :show

    # Dunning
    get "/dunning", DunningController, :index
    get "/dunning/:id", DunningController, :show
  end
end
