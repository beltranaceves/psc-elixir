defmodule Psc.Insights.Context do
  @moduledoc """
  Everything a detector may read.

  Detectors are pure functions of this struct: `cells` is the editor's
  in-memory map (so unsaved and remote edits are included), `touch_map` is the
  per-cell last-edit map folded from the event log, and `now` is injected so
  time-based findings are testable.
  """

  defstruct cells: %{},
            name: "",
            description: "",
            touch_map: %{},
            notes: [],
            now: nil,
            options: %{}

  @type t :: %__MODULE__{
          cells: map(),
          name: String.t(),
          description: String.t(),
          touch_map: map(),
          notes: [map()],
          now: DateTime.t(),
          options: map()
        }

  def new(cells, opts \\ []) do
    cells = cells || %{}

    %__MODULE__{
      cells: cells,
      name: text(cells["$name"]) || Keyword.get(opts, :name, ""),
      description: text(cells["$description"]) || Keyword.get(opts, :description, ""),
      touch_map: Keyword.get(opts, :touch_map) || %{},
      notes: Keyword.get(opts, :notes) || [],
      now: Keyword.get(opts, :now) || DateTime.utc_now(),
      options: Keyword.get(opts, :options, %{})
    }
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil
end
