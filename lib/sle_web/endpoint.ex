defmodule SLEWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :sle

  @session_options [
    store: :cookie,
    key: "_sle_key",
    signing_salt: "WEeOqtZQ",
    same_site: "Lax"
  ]

  plug Plug.Static,
    at: "/",
    from: :sle,
    gzip: not code_reloading?,
    only: SLEWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :sle
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SLEWeb.Router
end
