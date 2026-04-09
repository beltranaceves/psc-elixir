defmodule Psc.Canvas.UnstrCanvas do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "unstr_canvases" do
      field :name, :string
      field :description, :string

      field :shared_with, {:array, :id}, default: []

      belongs_to :author, Psc.Accounts.User, type: :id

      field :cells, :map, default: %{
        layout: [[], [], []],
        capabilities: nil,
        evolvability_cluster: nil,
        horizon: nil,
        inner_environment: nil,
        leverage: nil,
        manifestations: nil,
        merit_cluster: nil,
        mission: nil,
        outer_environment: nil,
        potential: nil,
        problem: nil,
        solution_cluster: nil,
      }
      timestamps()
    end

    def changeset(unstr_canvas, attrs) do
      # Add a step to validate that cells has the correct structure
      unstr_canvas
      |> cast(attrs, [:name, :description, :author_id, :shared_with, :cells])
      |> validate_required([:name, :author_id, :cells])
      |> validate_cells_structure()
    end

    defp validate_cells_structure(changeset) do
      # Validates that the cells field contains all the keys outlines in the layout 2d array
      validate_change(changeset, :cells, fn :cells, cells ->
        layout = get_in(cells, ["layout"])
        if is_list(layout) and Enum.all?(layout, &is_list/1) do
          # Flatten the layout to get all cell keys
          cell_keys = layout |> List.flatten() |> Enum.uniq()
          missing_keys = cell_keys -- Map.keys(cells)

          if missing_keys == [] do
            []
          else
            [cells: "Missing cell data for keys: #{Enum.join(missing_keys, ", ")}"]
          end
        else
          [cells: "Layout must be a 2D array of cell keys"]
        end
      end)
    end
end
