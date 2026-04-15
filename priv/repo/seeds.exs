# Seeds script for the Subscription Lifecycle Engine.
#
# Creates a default tenant on first run. Idempotent — does nothing
# if tenants already exist.
#
#     mix run priv/repo/seeds.exs

alias SLE.Repo
alias SLE.Tenants.Tenant

tenant_count = Repo.aggregate(Tenant, :count)

if tenant_count == 0 do
  tenant_name = System.get_env("DEFAULT_TENANT_NAME") || "Default"

  case SLE.Tenants.register(%{name: tenant_name}) do
    {:ok, tenant, api_key} ->
      IO.puts("=== Default tenant created ===")
      IO.puts("  Name:       #{tenant.name}")
      IO.puts("  ID:         #{tenant.id}")
      IO.puts("  API Key:    #{api_key}")
      IO.puts("  Prefix:     #{tenant.api_key_prefix}")
      IO.puts("")
      IO.puts("  Save this API key — it will not be shown again.")

    {:error, changeset} ->
      IO.puts("ERROR: Failed to create default tenant:")
      IO.inspect(changeset.errors)

    {:error, :registration_disabled} ->
      IO.puts("SKIP: Tenant registration is disabled (SELF_REGISTRATION_ENABLED=false)")
  end
else
  IO.puts("Seeds: #{tenant_count} tenant(s) already exist, skipping seed.")
end
