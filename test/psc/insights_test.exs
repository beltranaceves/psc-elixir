defmodule Psc.InsightsTest do
  use Psc.DataCase, async: true

  alias Psc.Accounts.Scope
  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.Insights
  alias Psc.Insights.Report
  alias Psc.InsightsFixtures

  setup do
    user = AccountsFixtures.user_fixture()

    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{
        "name" => "Insights canvas",
        "cells" =>
          InsightsFixtures.cells([
            {"Problem", "Teams need a faster onboarding path"},
            {"Risks", ""}
          ])
      })

    %{user: user, scope: Scope.for_user(user), canvas: canvas}
  end

  test "a run is stored and can be read back", %{scope: scope, canvas: canvas} do
    assert {:ok, report} = Insights.run(scope, canvas, canvas.cells)
    assert report.canvas_id == canvas.id
    assert report.mode == "heuristic"
    assert report.findings != []
    assert report.stats["cells"] == 2
    assert report.stats["fields"] == 2
    assert report.stats["filled"] == 1
    assert report.stats["empty_cells"] == 1

    stored = Insights.get_report(scope, canvas.id)
    assert stored.id == report.id
    assert length(stored.findings) == length(report.findings)
  end

  test "running again replaces the row instead of adding one", %{scope: scope, canvas: canvas} do
    {:ok, _report} = Insights.run(scope, canvas, canvas.cells)
    {:ok, second} = Insights.run(scope, canvas, canvas.cells)

    assert Repo.aggregate(Report, :count) == 1
    assert Insights.get_report(scope, canvas.id).id == second.id
  end

  test "another user cannot read or run the analysis", %{canvas: canvas} do
    other = Scope.for_user(AccountsFixtures.user_fixture())

    assert Insights.get_report(other, canvas.id) == nil
    assert {:error, :unauthorized} = Insights.run(other, canvas, canvas.cells)
  end

  test "a shared user can read and run it", %{scope: scope, canvas: canvas} do
    other = AccountsFixtures.user_fixture()
    {:ok, _canvas} = Canvas.update_unstr_canvas(canvas, %{"shared_with" => [other.email]})
    other_scope = Scope.for_user(other)

    assert {:ok, _report} = Insights.run(scope, canvas, canvas.cells)
    assert Insights.get_report(other_scope, canvas.id) != nil
  end

  test "dismiss and restore change only the stored list", %{scope: scope, canvas: canvas} do
    {:ok, report} = Insights.run(scope, canvas, canvas.cells)
    finding = hd(report.findings)

    assert {:ok, dismissed} = Insights.dismiss(scope, canvas.id, finding["id"])
    assert finding["id"] in dismissed.dismissed

    assert {:ok, restored} = Insights.restore(scope, canvas.id, finding["id"])
    refute finding["id"] in restored.dismissed
  end

  test "a re-run keeps the dismissal of a finding that still exists", %{
    scope: scope,
    canvas: canvas
  } do
    {:ok, report} = Insights.run(scope, canvas, canvas.cells)
    finding = hd(report.findings)
    {:ok, _} = Insights.dismiss(scope, canvas.id, finding["id"])

    {:ok, rerun} = Insights.run(scope, canvas, canvas.cells)
    assert finding["id"] in rerun.dismissed
  end

  test "a re-run drops the dismissal of a finding that no longer exists", %{
    scope: scope,
    canvas: canvas
  } do
    {:ok, report} = Insights.run(scope, canvas, canvas.cells)
    finding = hd(report.findings)
    {:ok, _} = Insights.dismiss(scope, canvas.id, finding["id"])

    filled = put_in(canvas.cells, ["r1_c2", "content"], "A populated risks cell")
    {:ok, rerun} = Insights.run(scope, canvas, filled)

    refute finding["id"] in rerun.dismissed
  end

  test "stale? detects a changed canvas and ignores map order", %{scope: scope, canvas: canvas} do
    {:ok, report} = Insights.run(scope, canvas, canvas.cells)

    refute Insights.stale?(report, canvas.cells)

    changed = put_in(canvas.cells, ["r1_c1", "content"], "A different problem")
    assert Insights.stale?(report, changed)

    reordered = canvas.cells |> Enum.reverse() |> Map.new()
    assert Insights.fingerprint(canvas.cells) == Insights.fingerprint(reordered)
  end

  test "the AI pass reports a missing connection instead of crashing", %{
    scope: scope,
    canvas: canvas
  } do
    {:ok, report} = Insights.run(scope, canvas, canvas.cells)
    assert {:error, :no_connection} = Insights.enhance(scope, canvas, canvas.cells, report)
  end

  test "a save folds the edited cell's timestamp into touch_map", %{
    user: user,
    canvas: canvas
  } do
    assert {:ok, _seq} =
             Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
               "type" => "update_cell",
               "cell_key" => "r1_c1",
               "field" => "content",
               "value" => "Edited once"
             })

    assert {:ok, saved} = Canvas.save_unstr_canvas_content_to_db(canvas.id, canvas.cells)
    assert is_binary(saved.touch_map["r1_c1"])
    refute Map.has_key?(saved.touch_map, "r1_c2")
  end
end
