defmodule Psc.Insights.DetectorsTest do
  use ExUnit.Case, async: true

  alias Psc.Insights.Context
  alias Psc.Insights.Detectors.{Duplicate, Empty, Relevance, Stale}
  alias Psc.InsightsFixtures

  @now ~U[2026-10-27 12:00:00Z]

  describe "empty" do
    test "reports blank cells as warnings and partially blank ones as info" do
      cells =
        InsightsFixtures.cells(
          [{"Problem", "Teams need faster onboarding"}, {"Risks", ""}],
          fields: ["content", "evidence"]
        )

      findings = Empty.run(Context.new(cells, now: @now))

      blank = Enum.find(findings, &(&1["cell_keys"] == ["r1_c2"]))
      partial = Enum.find(findings, &(&1["cell_keys"] == ["r1_c1"]))

      assert blank["severity"] == "warning"
      assert blank["kind"] == "empty"
      assert partial["severity"] == "info"
      assert partial["kind"] == "empty"
    end

    test "reports a completely empty canvas once at canvas level" do
      cells = InsightsFixtures.cells([{"Problem", ""}, {"Risks", ""}])
      findings = Empty.run(Context.new(cells, now: @now))

      assert Enum.any?(findings, &(&1["kind"] == "coverage" and &1["cell_keys"] == []))
    end

    test "stays silent for a well-filled canvas" do
      cells =
        InsightsFixtures.cells([
          {"Problem", "A clear problem statement"},
          {"Solution", "A clear solution statement"}
        ])

      findings = Empty.run(Context.new(cells, now: @now))
      refute Enum.any?(findings, &(&1["kind"] == "coverage"))
      refute Enum.any?(findings, &(&1["kind"] == "empty"))
    end
  end

  describe "duplicate" do
    test "finds two fields with the same text" do
      text =
        "Customer discovery interviews revealed a strong need for faster onboarding in the product"

      cells =
        InsightsFixtures.cells([
          {"Problem", text},
          {"Evidence", text},
          {"Risks", "Pricing may become a blocker once the trial period ends."}
        ])

      findings = Duplicate.run(Context.new(cells, now: @now))

      assert [%{"cell_keys" => keys, "kind" => "duplicate"}] = findings
      assert Enum.sort(keys) == ["r1_c1", "r1_c2"]
    end

    test "does not flag clearly different content" do
      cells =
        InsightsFixtures.cells([
          {"Problem", "Teams cannot find the onboarding checklist inside the product."},
          {"Solution", "Add a persistent checklist to the workspace sidebar for new teams."}
        ])

      assert Duplicate.run(Context.new(cells, now: @now)) == []
    end
  end

  describe "relevance" do
    test "flags the cell that shares no vocabulary with the rest" do
      cells =
        InsightsFixtures.cells([
          {"Interviews",
           "Customer discovery interviews show teams struggle with onboarding because the product workflow is unclear and requires too much manual effort"},
          {"Sessions",
           "Onboarding interviews reveal the product workflow confuses new teams during customer discovery sessions and creates friction in their daily work"},
          {"Notes",
           "Teams said the onboarding workflow needs clearer product guidance during customer discovery sessions so they can complete setup without asking support"},
          {"Findings",
           "Customer discovery sessions show onboarding workflow problems for new teams using the product and reveal where guidance is missing"},
          {"Appendix",
           "Quantum chromodynamics lattice simulations require careful renormalisation of gluon propagators and nonperturbative corrections at finite temperature"}
        ])

      findings = Relevance.run(Context.new(cells, now: @now))

      assert [%{"cell_keys" => ["r1_c5"], "kind" => "relevance", "severity" => "info"}] = findings
    end

    test "stays silent on a canvas with too little text" do
      cells =
        InsightsFixtures.cells([
          {"A", "short"},
          {"B", "also short"},
          {"C", "still short"},
          {"D", "short too"}
        ])

      assert Relevance.run(Context.new(cells, now: @now)) == []
    end
  end

  describe "stale" do
    test "flags a cell left behind while the canvas is being edited" do
      cells = InsightsFixtures.cells([{"Problem", "Old thinking"}, {"Risks", "Fresh thinking"}])

      context =
        Context.new(cells,
          now: @now,
          touch_map: %{
            "r1_c1" => @now |> DateTime.add(-40, :day) |> DateTime.to_iso8601(),
            "r1_c2" => @now |> DateTime.add(-1, :day) |> DateTime.to_iso8601()
          }
        )

      assert [%{"cell_keys" => ["r1_c1"], "kind" => "stale", "severity" => "warning"}] =
               Stale.run(context)
    end

    test "stays silent when every cell is equally old" do
      cells = InsightsFixtures.cells([{"Problem", "Old"}, {"Risks", "Also old"}])

      context =
        Context.new(cells,
          now: @now,
          touch_map: %{
            "r1_c1" => @now |> DateTime.add(-90, :day) |> DateTime.to_iso8601(),
            "r1_c2" => @now |> DateTime.add(-91, :day) |> DateTime.to_iso8601()
          }
        )

      assert Stale.run(context) == []
    end

    test "stays silent without touch data" do
      cells = InsightsFixtures.cells([{"Problem", "Old"}, {"Risks", "Fresh"}])
      assert Stale.run(Context.new(cells, now: @now)) == []
    end
  end
end
