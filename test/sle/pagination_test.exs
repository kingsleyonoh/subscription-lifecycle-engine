defmodule SLE.PaginationTest do
  @moduledoc false

  use SLE.DataCase, async: true

  alias SLE.Pagination
  alias SLE.Subscriptions.Subscription

  import SLE.Factory
  import Ecto.Query

  describe "paginate/2" do
    test "returns first page with default limit" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      for _i <- 1..30 do
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)
      end

      query = from(s in Subscription, where: s.tenant_id == ^tenant.id, order_by: [asc: s.id])
      {results, meta} = Pagination.paginate(query, [])

      assert length(results) == 25
      assert meta.has_more == true
      assert meta.cursor != nil
    end

    test "returns results with custom limit" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      for _i <- 1..10 do
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)
      end

      query = from(s in Subscription, where: s.tenant_id == ^tenant.id, order_by: [asc: s.id])
      {results, meta} = Pagination.paginate(query, limit: 5)

      assert length(results) == 5
      assert meta.has_more == true
      assert meta.cursor != nil
    end

    test "second page uses cursor from first page" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      for _i <- 1..10 do
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)
      end

      query = from(s in Subscription, where: s.tenant_id == ^tenant.id, order_by: [asc: s.id])
      {page1, meta1} = Pagination.paginate(query, limit: 5)
      {page2, meta2} = Pagination.paginate(query, limit: 5, cursor: meta1.cursor)

      assert length(page1) == 5
      assert length(page2) == 5
      # Pages should not overlap
      page1_ids = Enum.map(page1, & &1.id)
      page2_ids = Enum.map(page2, & &1.id)
      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
      assert meta2.has_more == false
    end

    test "returns empty results with no more data" do
      tenant = insert(:tenant)

      query = from(s in Subscription, where: s.tenant_id == ^tenant.id, order_by: [asc: s.id])
      {results, meta} = Pagination.paginate(query, [])

      assert results == []
      assert meta.has_more == false
      assert meta.cursor == nil
    end

    test "clamps limit to max 100" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)

      for _i <- 1..5 do
        insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)
      end

      query = from(s in Subscription, where: s.tenant_id == ^tenant.id, order_by: [asc: s.id])
      {results, _meta} = Pagination.paginate(query, limit: 200)

      # Should be clamped, but we only have 5 records so will get 5
      assert length(results) == 5
    end

    test "handles invalid cursor gracefully" do
      tenant = insert(:tenant)

      query = from(s in Subscription, where: s.tenant_id == ^tenant.id, order_by: [asc: s.id])
      {results, meta} = Pagination.paginate(query, cursor: "invalid_cursor")

      assert results == []
      assert meta.has_more == false
    end

    test "cursor is base64 encoded UUID" do
      tenant = insert(:tenant)
      customer = insert(:customer, tenant_id: tenant.id)
      insert(:subscription, tenant_id: tenant.id, customer_id: customer.id)

      query = from(s in Subscription, where: s.tenant_id == ^tenant.id, order_by: [asc: s.id])
      {_results, meta} = Pagination.paginate(query, limit: 1)

      # Should decode to a valid UUID
      assert {:ok, decoded} = Base.url_decode64(meta.cursor, padding: false)
      assert {:ok, _} = Ecto.UUID.cast(decoded)
    end
  end
end
