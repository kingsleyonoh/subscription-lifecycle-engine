defmodule SLEWeb.ChangesetJSONTest do
  use SLEWeb.ConnCase, async: true

  @moduledoc false

  alias SLEWeb.ChangesetJSON

  describe "error/1 with changeset" do
    test "transforms changeset errors into PRD error format" do
      changeset =
        {%{}, %{name: :string}}
        |> Ecto.Changeset.cast(%{}, [:name])
        |> Ecto.Changeset.validate_required([:name])

      result = ChangesetJSON.error(%{changeset: changeset})

      assert result.error.code == "VALIDATION_ERROR"
      assert result.error.message == "Validation failed"
      assert [%{field: "name", message: "can't be blank"}] = result.error.details
    end

    test "handles multiple field errors" do
      changeset =
        {%{}, %{name: :string, email: :string}}
        |> Ecto.Changeset.cast(%{}, [:name, :email])
        |> Ecto.Changeset.validate_required([:name, :email])

      result = ChangesetJSON.error(%{changeset: changeset})

      assert length(result.error.details) == 2

      fields = Enum.map(result.error.details, & &1.field)
      assert "name" in fields
      assert "email" in fields
    end

    test "handles multiple errors on a single field" do
      changeset =
        {%{}, %{name: :string}}
        |> Ecto.Changeset.cast(%{"name" => ""}, [:name])
        |> Ecto.Changeset.validate_required([:name])
        |> Ecto.Changeset.validate_length(:name, min: 3)

      result = ChangesetJSON.error(%{changeset: changeset})

      name_errors =
        result.error.details
        |> Enum.filter(&(&1.field == "name"))

      assert name_errors != []
    end
  end
end
