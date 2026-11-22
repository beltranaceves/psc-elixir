defmodule Psc.Insights.OverviewTest do
  use ExUnit.Case, async: true

  alias Psc.Insights.Overview
  alias Psc.InsightsFixtures

  @now ~U[2026-11-24 12:00:00Z]

  defp cells do
    InsightsFixtures.cells([
      {"Problem", "Teams need a much faster onboarding path today"},
      {"Risks", "Cost"},
      {"Channels", ""}
    ])
  end

  defp tiles(touch_map, stats, users \\ %{}) do
    cells()
    |> Overview.build(touch_map, stats, users, @now)
    |> Map.new(&{&1.id, &1})
  end

  test "cell tiles come from the content and the touch map" do
    touch_map = %{
      "r1_c1" => "2026-11-23T12:00:00Z",
      "r1_c2" => "2026-11-10T12:00:00Z"
    }

    tiles = tiles(touch_map, %{"cells" => %{"r1_c1" => 7, "r1_c2" => 2, "gone" => 99}})

    assert tiles["oldest"].cell_key == "r1_c2"
    assert tiles["oldest"].detail == "Last edited 14 d ago"
    # A count for a cell that no longer exists is ignored.
    assert tiles["most_changed"].cell_key == "r1_c1"
    assert tiles["most_changed"].detail == "7 edits"
    assert tiles["longest"].cell_key == "r1_c1"
    assert tiles["longest"].detail == "8 words"
    # The empty cell is not the shortest: shortest is among cells with text.
    assert tiles["shortest"].cell_key == "r1_c2"
    assert tiles["shortest"].detail == "1 word"
  end

  test "people tiles come from the edit statistics" do
    stats = %{
      "users" => %{
        "1" => %{"edits" => 40, "added" => 1200, "removed" => 100},
        "2" => %{"edits" => 3, "added" => 5, "removed" => 90},
        "3" => %{"edits" => 9, "added" => 50, "removed" => 10}
      }
    }

    tiles = tiles(%{}, stats, %{"1" => "ana", "2" => "sam"})

    assert tiles["most_edits"].value == "ana"
    assert tiles["most_edits"].detail == "40 edits"
    assert tiles["fewest_edits"].value == "sam"
    assert tiles["net_added"].value == "ana"
    assert tiles["net_added"].detail == "+1,100 chars"
    assert tiles["net_added"].tone == :positive
    assert tiles["net_removed"].value == "sam"
    assert tiles["net_removed"].detail == "−85 chars"
  end

  test "an id with no account left is shown as a former member" do
    stats = %{"users" => %{"9" => %{"edits" => 5, "added" => 3, "removed" => 0}}}

    assert tiles(%{}, stats)["most_edits"].value == "Former member"
  end

  test "without data every tile says so instead of guessing" do
    tiles = tiles(%{}, %{"users" => %{"1" => %{"edits" => 2, "added" => 0, "removed" => 0}}})

    assert tiles["oldest"].value == nil
    assert tiles["most_changed"].value == nil
    assert tiles["fewest_edits"].value == nil
    assert tiles["fewest_edits"].detail == "Needs two or more editors"
    assert tiles["net_added"].value == nil
    assert tiles["net_removed"].value == nil
  end

  test "counting_since/1 reads the start of the counts" do
    assert Overview.counting_since(%{"since" => "2026-11-01T00:00:00Z"}) ==
             ~U[2026-11-01 00:00:00Z]

    assert Overview.counting_since(%{}) == nil
  end
end
