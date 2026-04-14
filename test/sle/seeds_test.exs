defmodule SLE.SeedsTest do
  @moduledoc false

  # Cannot be async because seeds.exs uses Repo directly (no sandbox checkout).
  # We use a manual sandbox checkout to keep these tests isolated.
  use ExUnit.Case

  alias SLE.Repo
  alias SLE.Tenants.Tenant

  setup do
    # Manually checkout the sandbox for this test process
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SLE.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(SLE.Repo, {:shared, self()})

    # Delete tenants within the sandbox transaction
    Repo.delete_all(Tenant)

    on_exit(fn ->
      # Cleanup env var side effects
      System.delete_env("DEFAULT_TENANT_NAME")
    end)

    :ok
  end

  describe "seeds.exs" do
    test "creates default tenant when no tenants exist" do
      assert Repo.aggregate(Tenant, :count) == 0

      run_seeds()

      assert Repo.aggregate(Tenant, :count) == 1
      tenant = Repo.one!(Tenant)
      assert tenant.name == "Default"
      assert tenant.is_active == true
      assert tenant.api_key_hash != nil
      assert tenant.api_key_prefix != nil
    end

    test "is idempotent — does not create duplicates on second run" do
      assert Repo.aggregate(Tenant, :count) == 0

      run_seeds()
      assert Repo.aggregate(Tenant, :count) == 1

      run_seeds()
      assert Repo.aggregate(Tenant, :count) == 1
    end

    test "respects DEFAULT_TENANT_NAME env var" do
      System.put_env("DEFAULT_TENANT_NAME", "Custom Tenant")

      run_seeds()

      tenant = Repo.one!(Tenant)
      assert tenant.name == "Custom Tenant"
    end
  end

  defp run_seeds do
    Code.eval_file("priv/repo/seeds.exs")
  end
end
