defmodule PscWeb.CanvasAnalysisLiveTest do
  # The AI test replaces the provider call for the whole node.
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Psc.Accounts.Scope
  alias Psc.Agent.Connections
  alias Psc.Canvas
  alias Psc.Insights
  alias Psc.Insights.Finding
  alias Psc.InsightsFixtures

  setup :register_and_log_in_user

  defp canvas_for(user) do
    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{
        "name" => "Analysis test",
        "cells" =>
          InsightsFixtures.cells(
            [
              {"Problem", "Teams need a faster onboarding path"},
              {"Risks", ""}
            ],
            name: "Analysis test"
          )
      })

    canvas
  end

  describe "the empty state" do
    test "explains the feature and offers a run", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      assert has_element?(lv, "#canvas-analysis-empty")
      assert has_element?(lv, "#canvas-analysis-run")
      assert has_element?(lv, "#canvas-analysis-ai-hint")
      refute has_element?(lv, "#canvas-analysis-ai")
    end
  end

  describe "running the analysis" do
    test "renders findings and a summary", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      lv |> element("#canvas-analysis-run") |> render_click()

      assert has_element?(lv, "#canvas-analysis-results")
      assert has_element?(lv, "#canvas-analysis-findings li")
      assert has_element?(lv, "#canvas-analysis-summary", "finding")
      assert has_element?(lv, "#canvas-analysis-copy")
      refute has_element?(lv, "#canvas-analysis-empty")

      assert render(element(lv, "#canvas-analysis-report-text")) =~ "Analysis — Analysis test"

      report = Insights.get_report(Scope.for_user(user), canvas.id)
      assert report
      assert report.stats["cells"] == 2
    end

    test "a finding's cell chip links back to the editor", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")
      lv |> element("#canvas-analysis-run") |> render_click()

      report = Insights.get_report(Scope.for_user(user), canvas.id)

      key =
        report.findings
        |> Enum.find(&(&1["cell_keys"] != []))
        |> Map.get("cell_keys")
        |> hd()

      assert has_element?(
               lv,
               ~s{a[href="/canvas/#{canvas.id}?tab=editor&cell=#{key}"]}
             )
    end

    test "the URL cell contract focuses the cell", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, _lv, html} = live(conn, ~p"/canvas/#{canvas.id}?tab=editor&cell=r1_c1")

      assert html =~ ~s{data-cell-focused="true"}
    end

    test "editing the canvas marks the report stale", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")
      lv |> element("#canvas-analysis-run") |> render_click()

      refute has_element?(lv, "#canvas-analysis-stale")

      render_hook(lv, "update_cell", %{
        "cell_key" => "r1_c1",
        "field" => "content",
        "value" => "A different problem"
      })

      assert has_element?(lv, "#canvas-analysis-stale")
    end
  end

  describe "dismissing" do
    test "hides the finding and the dismissed filter brings it back", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")
      lv |> element("#canvas-analysis-run") |> render_click()

      report = Insights.get_report(Scope.for_user(user), canvas.id)
      finding = report.findings |> Enum.find(&(&1["kind"] == "empty"))
      dom_id = Finding.dom_id(finding)

      assert has_element?(lv, "##{dom_id}")

      lv |> element("##{dom_id} button", "Dismiss") |> render_click()

      refute has_element?(lv, "##{dom_id}")
      assert has_element?(lv, "#canvas-analysis-filter-dismissed")

      lv |> element("#canvas-analysis-filter-dismissed") |> render_click()
      assert has_element?(lv, "##{dom_id}")

      lv |> element("##{dom_id} button", "Restore") |> render_click()
      refute has_element?(lv, "#canvas-analysis-filter-dismissed")
    end
  end

  describe "the AI toggle" do
    test "appears only when the user has a connection", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, _connection} =
        Connections.create(user, %{
          "name" => "Test key",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-test-12345678"
        })

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      assert has_element?(lv, "#canvas-analysis-ai")
      refute has_element?(lv, "#canvas-analysis-ai-hint")
      refute has_element?(lv, "#canvas-analysis-notes")

      lv |> element("#canvas-analysis-ai") |> render_click()
      assert has_element?(lv, "#canvas-analysis-connection")
      assert has_element?(lv, "#canvas-analysis-ai[aria-pressed=\"true\"]")
      assert has_element?(lv, "#canvas-analysis-notes")

      lv |> element("#canvas-analysis-notes") |> render_click()
      assert has_element?(lv, "#canvas-analysis-notes[aria-pressed=\"true\"]")
    end

    test "is hidden without a connection", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      refute has_element?(lv, "#canvas-analysis-ai")
      refute has_element?(lv, "#canvas-analysis-notes")
      assert has_element?(lv, "#canvas-analysis-ai-hint")
    end
  end
end
