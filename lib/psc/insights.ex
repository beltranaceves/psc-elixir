defmodule Psc.Insights do
  @moduledoc """
  Content analysis for one canvas.

  A run reads the editor's current `cells` map (not a fresh database read, so
  unsaved and remote edits are included), executes the deterministic detectors
  in `Psc.Insights.Analysis`, and upserts the result into `canvas_insights`.
  There is one row per canvas; findings are stored inside it so the free-tier
  row ceiling is not spent on analysis.

  AI is a second pass (`enhance/4`) over the stored heuristic report. It uses
  the user's own provider connection and appends attributed findings; when it
  fails, the heuristic report remains.

  Every public function takes the caller's `current_scope`, and access is the
  canvas's access rule: the author or someone it is shared with.
  """

  alias Psc.Agent.Connection
  alias Psc.Canvas
  import Ecto.Query, only: [from: 2]

  alias Psc.Insights.{Analysis, Context, LLM, Overview, Report}
  alias Psc.Repo

  @doc "The cached analysis for a canvas, or nil when it has never been run."
  def get_report(scope, canvas_id) do
    with %{} = canvas <- Canvas.get_unstr_canvas_with_author(canvas_id),
         true <- authorized?(scope, canvas) do
      Repo.get_by(Report, canvas_id: canvas.id)
    else
      _other -> nil
    end
  end

  @doc """
  Runs the deterministic analysis and stores it.

  Options: `:now` (a fixed `DateTime` in tests), `:touch_map` (the editor's
  in-memory copy), `:detectors` (a subset, in tests).
  """
  def run(scope, canvas, cells, opts \\ []) do
    with true <- authorized?(scope, canvas) do
      now = Keyword.get(opts, :now) || DateTime.utc_now()

      context =
        Context.new(cells,
          name: canvas.name,
          description: canvas.description || "",
          touch_map: Keyword.get(opts, :touch_map) || canvas.touch_map || %{},
          now: now,
          options: Keyword.get(opts, :options, %{})
        )

      result = Analysis.run(context, opts)
      existing = Repo.get_by(Report, canvas_id: canvas.id)

      # The AI review runs on demand, so a heuristic re-run keeps its findings
      # (and their attribution) instead of discarding a paid-for answer.
      findings = Analysis.merge(result.findings, ai_findings(existing))
      dismissed = keep_live_dismissals(existing, findings)

      report = %Report{
        canvas_id: canvas.id,
        fingerprint: fingerprint(cells),
        snapshot_seq: canvas.snapshot_seq || 0,
        computed_at: now,
        mode: (existing && existing.mode) || "heuristic",
        provider: existing && existing.provider,
        model: existing && existing.model,
        ai_fingerprint: existing && existing.ai_fingerprint,
        ai_computed_at: existing && existing.ai_computed_at,
        findings: findings,
        dismissed: dismissed,
        stats: result.stats
      }

      persist(report)
    else
      false -> {:error, :unauthorized}
    end
  end

  @doc """
  Adds the optional AI findings to a stored heuristic report.

  Options: `:include_notes` appends the canvas's notes to the prompt.

  Returns the updated report. A missing connection is `{:error,
  :no_connection}`; a provider failure returns its message so the interface can
  report it without discarding the heuristic results.
  """
  def enhance(scope, canvas, cells, %Report{} = report, opts \\ []) do
    with true <- authorized?(scope, canvas),
         {:ok, result} <- LLM.review(context_for(canvas, cells, opts), scope.user) do
      # A new review replaces the previous AI findings; the heuristic ones stay.
      heuristic = Enum.reject(report.findings, &(&1["source"] == "ai"))
      findings = Analysis.merge(heuristic, result.findings)

      %{
        report
        | mode: "assisted",
          provider: result.provider,
          model: result.model,
          findings: findings,
          dismissed: keep_live_dismissals(report, findings),
          ai_fingerprint: fingerprint(cells),
          ai_computed_at: DateTime.utc_now()
      }
      |> persist()
    else
      false -> {:error, :unauthorized}
      {:error, _reason} = error -> error
    end
  end

  @doc "Hides a finding for everyone who can open the canvas."
  def dismiss(scope, canvas_id, finding_id) when is_binary(finding_id) do
    update_dismissed(scope, canvas_id, fn dismissed -> Enum.uniq([finding_id | dismissed]) end)
  end

  @doc "Brings a dismissed finding back."
  def restore(scope, canvas_id, finding_id) when is_binary(finding_id) do
    update_dismissed(scope, canvas_id, fn dismissed -> List.delete(dismissed, finding_id) end)
  end

  @doc "Whether the canvas has changed since the report was computed."
  def stale?(nil, _cells), do: false
  def stale?(%Report{} = report, cells), do: report.fingerprint != fingerprint(cells)

  @doc "Whether the canvas has changed since the last AI review (false without one)."
  def ai_stale?(%Report{ai_fingerprint: ai_hash}, cells) when is_binary(ai_hash),
    do: ai_hash != fingerprint(cells)

  def ai_stale?(_report, _cells), do: false

  @doc """
  The overview tiles for a canvas (`Psc.Insights.Overview`).

  `cells` and `touch_map` are the editor's in-memory copies, so unsaved edits
  count. Returns `{:ok, %{tiles: tiles, since: since}}`, where `since` is when
  the edit counts started, or `{:error, :unauthorized}`.
  """
  def overview(scope, canvas, cells, touch_map, now \\ DateTime.utc_now()) do
    if authorized?(scope, canvas) do
      stats = Canvas.unstr_canvas_edit_stats(canvas)

      {:ok,
       %{
         tiles: Overview.build(cells, touch_map, stats, user_names(stats), now),
         since: Overview.counting_since(stats)
       }}
    else
      {:error, :unauthorized}
    end
  end

  # Display names for the people in the statistics: the part of the address
  # before the @, which is what the presence avatars show as well.
  defp user_names(stats) do
    ids =
      (stats["users"] || %{})
      |> Map.keys()
      |> Enum.flat_map(fn id ->
        case Integer.parse(id) do
          {n, ""} -> [n]
          _other -> []
        end
      end)

    from(u in Psc.Accounts.User, where: u.id in ^ids, select: {u.id, u.email})
    |> Repo.all()
    |> Map.new(fn {id, email} -> {to_string(id), email |> String.split("@") |> hd()} end)
  end

  defp ai_findings(nil), do: []

  defp ai_findings(%Report{findings: findings}),
    do: Enum.filter(findings, &(&1["source"] == "ai"))

  @doc "A stable hash of the cells map, used to detect drift from a run."
  def fingerprint(cells) do
    :crypto.hash(:sha256, :erlang.term_to_binary(canonical(cells)))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  @doc "Whether the user has a connection the AI pass can use."
  def ai_available?(user), do: LLM.available?(user)

  @doc "The connection label shown next to the AI toggle, or nil."
  def ai_connection_label(user) do
    user
    |> LLM.connection()
    |> LLM.connection_label()
  end

  @doc "The provider/model a stored assisted report used."
  def attribution(%Report{provider: nil}), do: nil

  def attribution(%Report{provider: provider, model: model}) do
    [Connection.provider_label(provider), model]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp update_dismissed(scope, canvas_id, fun) do
    case get_report(scope, canvas_id) do
      %Report{} = report ->
        report
        |> Ecto.Changeset.change(dismissed: fun.(report.dismissed))
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @max_notes 10

  defp context_for(canvas, cells, opts) do
    Context.new(cells,
      name: canvas.name,
      description: canvas.description || "",
      touch_map: canvas.touch_map || %{},
      notes: notes_for(canvas.id, opts)
    )
  end

  defp notes_for(canvas_id, opts) do
    if Keyword.get(opts, :include_notes, false) do
      canvas_id
      |> Psc.Notes.list_notes()
      |> Enum.take(@max_notes)
      |> Enum.map(fn note ->
        %{"title" => note.title, "content" => Psc.Notes.get_note_content(note.id)}
      end)
    else
      []
    end
  end

  defp keep_live_dismissals(nil, _findings), do: []

  defp keep_live_dismissals(%Report{dismissed: dismissed}, findings) do
    ids = MapSet.new(findings, & &1["id"])
    Enum.filter(dismissed, &MapSet.member?(ids, &1))
  end

  defp persist(%Report{} = report) do
    attrs = %{
      canvas_id: report.canvas_id,
      fingerprint: report.fingerprint,
      snapshot_seq: report.snapshot_seq,
      computed_at: report.computed_at,
      mode: report.mode,
      provider: report.provider,
      model: report.model,
      findings: report.findings,
      dismissed: report.dismissed,
      stats: report.stats,
      ai_fingerprint: report.ai_fingerprint,
      ai_computed_at: report.ai_computed_at
    }

    %Report{}
    |> Report.changeset(attrs)
    |> Repo.insert(
      on_conflict: {
        :replace,
        [
          :fingerprint,
          :snapshot_seq,
          :computed_at,
          :mode,
          :provider,
          :model,
          :findings,
          :dismissed,
          :stats,
          :ai_fingerprint,
          :ai_computed_at,
          :updated_at
        ]
      },
      conflict_target: :canvas_id,
      returning: true
    )
  end

  defp authorized?(%{user: %{email: email}}, canvas) do
    Canvas.can_access_unstr_canvas?(canvas, email)
  end

  defp authorized?(_scope, _canvas), do: false

  # Deterministic serialisation: map keys are sorted before hashing, so two
  # maps with the same content always produce the same fingerprint.
  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)

  defp canonical(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> canonical() |> List.to_tuple()
  end

  defp canonical(other), do: other
end
