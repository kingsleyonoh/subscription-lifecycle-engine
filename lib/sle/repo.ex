defmodule SLE.Repo do
  use Ecto.Repo,
    otp_app: :sle,
    adapter: Ecto.Adapters.Postgres
end
