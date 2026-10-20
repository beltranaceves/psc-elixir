defmodule Psc.Repo.Migrations.AddNotesModeToUnstrCanvases do
  use Ecto.Migration

  @moduledoc """
  Adds the canvas's note mode.

  A template decides whether its canvases get a list of notes ("multi") or a
  single scratchpad ("single"). The setting lives in the template's
  `layout_map` and is copied onto the canvas when it is instantiated.
  """

  def change do
    alter table(:unstr_canvases) do
      # "multi" — a list of notes. "single" — one scratchpad for the canvas.
      add :notes_mode, :string, default: "multi", null: false
    end
  end
end
