defmodule Psc.Repo.Migrations.DropDocuments do
  use Ecto.Migration

  @moduledoc """
  Retires the standalone documents section.

  The section was parked and unlinked in ADR-018: notes are the integration it
  anticipated, and they live inside a canvas. The documents tables go with it;
  the collaborative-text machinery they used now serves the notes.

  The rows are dropped rather than migrated: the only document in the deployed
  database was a deployment smoke-test artefact, and the section was never
  reachable from the UI.
  """

  def change do
    drop table(:document_events)
    drop table(:documents)
  end
end
