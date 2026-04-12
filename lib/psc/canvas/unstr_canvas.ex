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
        "columns" => [
          %{"id" => "perceive", "label" => "Perceive"},
          %{"id" => "form", "label" => "Form"},
          %{"id" => "consolidate", "label" => "Consolidate"},
          %{"id" => "learn", "label" => "Learn"}
        ],
        "rows" => [
          %{"id" => "rationale", "label" => "Rationale"},
          %{"id" => "strategy", "label" => "Strategy"},
          %{"id" => "tactics", "label" => "Tactics"}
        ],
        "layout" => [
          ["problem", "leverage", "solution_cluster", "horizon"],
          ["outer_environment", "inner_environment", "evolvability_cluster", "potential"],
          ["manifestations", "capabilities", "merit_cluster", "mission"]
        ],
        "problem" => %{
          "row" => "rationale",
          "column" => "perceive",
          "content" => ""
        },
        "leverage" => %{
          "row" => "rationale",
          "column" => "form",
          "technology" => "",
          "components" => "",
          "information" => "",
          "human_resources" => ""
        },
        "solution_cluster" => %{
          "row" => "rationale",
          "column" => "consolidate",
          "content" => ""
        },
        "horizon" => %{
          "row" => "rationale",
          "column" => "learn",
          "content" => ""
        },
        "outer_environment" => %{
          "row" => "strategy",
          "column" => "perceive",
          "external_services" => "",
          "external_implements" => "",
          "external_repositories" => "",
          "external_people" => ""
        },
        "inner_environment" => %{
          "row" => "strategy",
          "column" => "form",
          "content" => ""
        },
        "evolvability_cluster" => %{
          "row" => "strategy",
          "column" => "consolidate",
          "evolvability" => "",
          "diffusibility" => "",
          "adoptability" => ""
        },
        "potential" => %{
          "row" => "strategy",
          "column" => "learn",
          "content" => ""
        },
        "manifestations" => %{
          "row" => "tactics",
          "column" => "perceive",
          "content" => ""
        },
        "capabilities" => %{
          "row" => "tactics",
          "column" => "form",
          "content" => ""
        },
        "merit_cluster" => %{
          "row" => "tactics",
          "column" => "consolidate",
          "merit" => "",
          "value" => "",
          "reservation" => "",
          "rebuttal" => ""
        },
        "mission" => %{
          "row" => "tactics",
          "column" => "learn",
          "content" => ""
        }
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
      # Validates that the cells field contains all the keys outlined in the layout 2d array
      validate_change(changeset, :cells, fn :cells, cells ->
        layout = get_in(cells, ["layout"])
        if is_list(layout) and Enum.all?(layout, &is_list/1) do
          # Flatten the layout to get all cell keys
          cell_keys = layout |> List.flatten() |> Enum.uniq()

          # Metadata keys that should be excluded from cell validation
          metadata_keys = ["columns", "rows", "layout"]
          all_cell_keys = cells |> Map.keys() |> Enum.reject(&(&1 in metadata_keys))

          missing_keys = cell_keys -- all_cell_keys

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
