defmodule SLEWeb.Router do
  use SLEWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SLEWeb do
    pipe_through :api
  end
end
