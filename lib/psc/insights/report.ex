defmodule Psc.Insights.Report do
  @moduledoc """
  The latest analysis of one canvas.

  There is exactly one row per canvas (`canvas_id` is unique). The findings are
  stored as a JSONB array rather than as rows of their own: the deployed
  free-tier Postgres caps every table at 10k rows, and an analysis produces a
  handful of findings at a time.

  `fingerprint` is the hash of the `cells` map the analysis ran against, so the
  interface can tell whether the canvas has changed since. `dismissed` holds
  finding ids, and is shared by everyone who can open the canvas, like the
  findings themselves.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "canvas_insights" do
    field :fingerprint, :string
    field :snapshot_seq, :integer, default: 0
    field :computed_at, :utc_datetime_usec
    field :mode, :string, default: "heuristic"
    field :provider, :string
    field :model, :string
    field :findings, {:array, :map}, default: []
    field :dismissed, {:array, :string}, default: []
    field :stats, :map, default: %{}

    belongs_to :canvas, Psc.Canvas.UnstrCanvas, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :canvas_id,
      :fingerprint,
      :snapshot_seq,
      :computed_at,
      :mode,
      :provider,
      :model,
      :findings,
      :dismissed,
      :stats
    ])
    |> validate_required([:canvas_id, :fingerprint, :computed_at])
    |> validate_inclusion(:mode, ["heuristic", "assisted"])
    |> foreign_key_constraint(:canvas_id)
  end
end
