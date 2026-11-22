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

  describe "opening the tab" do
    test "shows the overview and runs the heuristic checks", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      assert has_element?(lv, "#canvas-analysis-tiles")

      for id <-
            ~w(oldest most_changed longest shortest most_edits fewest_edits net_added net_removed) do
        assert has_element?(lv, "#overview-#{id}")
      end

      assert has_element?(lv, "#overview-longest", "Problem")
      assert has_element?(lv, "#canvas-analysis-since", "Edit counts start with the next save")

      # The heuristic checks ran without a click and were stored.
      assert has_element?(lv, "#canvas-analysis-results")
      assert has_element?(lv, "#canvas-analysis-findings li details")
      assert has_element?(lv, "#canvas-analysis-summary", "AI review not run")

      report = Insights.get_report(Scope.for_user(user), canvas.id)
      assert report.stats["cells"] == 2
    end

    test "a cell tile and a finding's cell chip link back to the editor", %{
      conn: conn,
      user: user
    } do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      assert has_element?(
               lv,
               ~s{#overview-longest[href="/canvas/#{canvas.id}?tab=editor&cell=r1_c1"]}
             )

      report = Insights.get_report(Scope.for_user(user), canvas.id)
      finding = Enum.find(report.findings, &(&1["cell_keys"] != []))
      key = hd(finding["cell_keys"])

      assert has_element?(
               lv,
               ~s{##{Finding.dom_id(finding)} a[href="/canvas/#{canvas.id}?tab=editor&cell=#{key}"]}
             )
    end

    test "the URL cell contract focuses the cell", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, _lv, html} = live(conn, ~p"/canvas/#{canvas.id}?tab=editor&cell=r1_c1")

      assert html =~ ~s{data-cell-focused="true"}
    end

    test "an edit marks the checks out of date and Refresh reruns them", %{
      conn: conn,
      user: user
    } do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")
      refute has_element?(lv, "#canvas-analysis-changed")

      render_hook(lv, "update_cell", %{
        "cell_key" => "r1_c2",
        "field" => "content",
        "value" => "Budget overrun"
      })

      assert has_element?(lv, "#canvas-analysis-changed")
      # There is no AI review yet, so there is nothing for it to be stale against.
      refute has_element?(lv, "#canvas-analysis-stale")

      lv |> element("#canvas-analysis-refresh") |> render_click()

      refute has_element?(lv, "#canvas-analysis-changed")
      assert has_element?(lv, "#overview-most_changed", "Risks")
      assert has_element?(lv, "#overview-most_edits", user.email |> String.split("@") |> hd())
    end

    test "low coverage is part of the Empty filter, not a kind of its own", %{
      conn: conn,
      user: user
    } do
      {:ok, canvas} =
        Canvas.create_unstr_canvas(user.id, %{
          "name" => "Mostly empty",
          "cells" =>
            InsightsFixtures.cells(
              [{"A", "Only this one"}, {"B", ""}, {"C", ""}, {"D", ""}],
              name: "Mostly empty"
            )
        })

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      report = Insights.get_report(Scope.for_user(user), canvas.id)
      coverage = Enum.find(report.findings, &(&1["cell_keys"] == []))
      assert coverage["kind"] == "empty"

      refute has_element?(lv, "#canvas-analysis-filter-coverage")
      assert has_element?(lv, "#canvas-analysis-filter-empty")

      lv |> element("#canvas-analysis-filter-empty") |> render_click()
      assert has_element?(lv, "##{Finding.dom_id(coverage)}")
    end
  end

  describe "dismissing" do
    test "hides the finding and the dismissed filter brings it back", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

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

  describe "the AI review" do
    defp connect_provider(user) do
      {:ok, _connection} =
        Connections.create(user, %{
          "name" => "Test key",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-test-12345678"
        })
    end

    test "runs on demand and its findings join the list", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      connect_provider(user)

      Application.put_env(:psc, :insights_llm, fn _prompt ->
        {:ok,
         ~s({"findings":[{"kind":"contradiction","severity":"warning","cell_keys":["r1_c1"],"title":"Speed versus cost","detail":"The cells disagree."}]})}
      end)

      on_exit(fn -> Application.delete_env(:psc, :insights_llm) end)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      refute has_element?(lv, "#canvas-analysis-findings", "Speed versus cost")
      assert has_element?(lv, "#canvas-analysis-connection")

      lv |> element("#canvas-analysis-ai-run") |> render_click()
      _ = render_async(lv)

      assert has_element?(lv, "#canvas-analysis-findings", "Speed versus cost")
      assert has_element?(lv, "#canvas-analysis-summary", "AI review just now")
      assert has_element?(lv, "#canvas-analysis-ai-run", "Run AI review again")

      render_hook(lv, "update_cell", %{
        "cell_key" => "r1_c2",
        "field" => "content",
        "value" => "Budget overrun"
      })

      assert has_element?(lv, "#canvas-analysis-stale")
    end

    test "the notes toggle appears with a connection", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      connect_provider(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      assert has_element?(lv, "#canvas-analysis-ai-run")
      refute has_element?(lv, "#canvas-analysis-ai-hint")

      lv |> element("#canvas-analysis-notes") |> render_click()
      assert has_element?(lv, "#canvas-analysis-notes[aria-pressed=\"true\"]")
    end

    test "is replaced by a settings hint without a connection", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=analysis")

      refute has_element?(lv, "#canvas-analysis-ai-run")
      refute has_element?(lv, "#canvas-analysis-notes")
      assert has_element?(lv, "#canvas-analysis-ai-hint")
    end
  end
end
