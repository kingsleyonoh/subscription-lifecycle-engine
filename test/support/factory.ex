defmodule SLE.Factory do
  @moduledoc """
  ExMachina factory for test data.

  Factories are added here as schemas are implemented.
  """

  use ExMachina.Ecto, repo: SLE.Repo

  alias SLE.Tenants.Tenant

  def tenant_factory do
    api_key = "sle_live_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
    hash = :crypto.hash(:sha256, api_key) |> Base.encode16(case: :lower)

    %Tenant{
      name: sequence(:tenant_name, &"Test Tenant #{&1}"),
      api_key_hash: hash,
      api_key_prefix: String.slice(api_key, 0, 13),
      stripe_config: %{},
      is_active: true
    }
  end
end
