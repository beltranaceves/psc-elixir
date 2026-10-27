defmodule Psc.Admin do
  @moduledoc """
  Read-only figures for the administration dashboard.

  This is not a second data layer: writes still go through `Psc.Canvas`,
  `Psc.Accounts` and `Psc.Notes`. Only counts and bounded listings live here, so
  the dashboard can show the instance's shape without loading rows.
  """

  import Ecto.Query, warn: false

  alias Psc.Repo
  alias Psc.Accounts.User
  alias Psc.Agent.Connection
  alias Psc.Canvas.{Layout, UnstrCanvas, UnstrCanvasEvent}
  alias Psc.Notes.{Note, NoteEvent}

  @trend_days 14
  @recent_limit 5
  @default_row_budget 10_000

  @doc """
  A map of the instance's row counts.

  `canvas_events` and `note_events` are both here because both event tables are
  pruned against the hosting plan's row ceiling.
  """
  def stats do
    %{
      users: count(User),
      admins: count(from(u in User, where: u.role == :admin)),
      unconfirmed_users: count(from(u in User, where: is_nil(u.confirmed_at))),
      templates: count(Layout),
      built_in_templates: count(from(l in Layout, where: l.built_in)),
      public_templates: count(from(l in Layout, where: l.public)),
      canvases: count(UnstrCanvas),
      notes: count(Note),
      canvas_events: count(UnstrCanvasEvent),
      note_events: count(NoteEvent),
      agent_connections: count(Connection)
    }
  end

  @doc """
  Per-day creation counts for the last `days` days, oldest first.

  Every list has exactly `days` entries, so a quiet day is a zero rather than a
  gap. Grouping happens in Postgres; only `days` rows per table come back.
  """
  def trends(days \\ @trend_days) do
    %{
      users: daily_counts(User, days),
      templates: daily_counts(Layout, days),
      canvases: daily_counts(UnstrCanvas, days),
      notes: daily_counts(Note, days)
    }
  end

  @doc """
  The most recently updated canvases and templates, with their authors.

  Both lists are bounded by `limit`; this is a dashboard preview, not a listing.
  """
  def recent(limit \\ @recent_limit) do
    %{
      canvases:
        Repo.all(
          from(c in UnstrCanvas,
            order_by: [desc: c.updated_at, desc: c.inserted_at],
            limit: ^limit,
            preload: [:author]
          )
        ),
      templates:
        Repo.all(
          from(l in Layout,
            order_by: [desc: l.updated_at, desc: l.inserted_at],
            limit: ^limit,
            preload: [:author]
          )
        )
    }
  end

  @doc """
  The per-table row ceiling of the hosting plan, used by the dashboard gauge.

  Override with `config :psc, :row_budget, 10_000`.
  """
  def row_budget, do: Application.get_env(:psc, :row_budget, @default_row_budget)

  @doc """
  The application version, or `"unknown"` when it cannot be read.
  """
  def version do
    case Application.spec(:psc, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end

  # The rows are always created in UTC; a naive boundary compares cleanly
  # against both `timestamp` and `timestamptz` columns.
  defp daily_counts(schema, days) do
    first_day = Date.add(Date.utc_today(), -(days - 1))
    since = NaiveDateTime.new!(first_day, ~T[00:00:00])

    counts =
      from(row in schema,
        where: row.inserted_at >= ^since,
        group_by: fragment("date_trunc('day', ?)::date", row.inserted_at),
        select: {fragment("date_trunc('day', ?)::date", row.inserted_at), count(row.id)}
      )
      |> Repo.all()
      |> Map.new()

    for offset <- 0..(days - 1), do: Map.get(counts, Date.add(first_day, offset), 0)
  end

  defp count(queryable), do: Repo.aggregate(queryable, :count, :id)
end
