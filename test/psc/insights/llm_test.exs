defmodule Psc.Insights.LLMTest do
  # `Application.put_env/3` replaces the provider call for the whole node, so
  # this module must not run alongside another test that needs the real one.
  use Psc.DataCase, async: false

  alias Psc.Accounts.Scope
  alias Psc.AccountsFixtures
  alias Psc.Agent.Connections
  alias Psc.Canvas
  alias Psc.Insights
  alias Psc.Insights.LLM
  alias Psc.InsightsFixtures

  setup do
    user = AccountsFixtures.user_fixture()

    {:ok, _connection} =
      Connections.create(user, %{
        "name" => "Test key",
        "provider" => "openai",
        "model_id" => "gpt-4.1-mini",
        "api_key" => "sk-test-12345678"
      })

    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{
        "name" => "AI canvas",
        "description" => "A canvas about onboarding",
        "cells" =>
          InsightsFixtures.cells(
            [
              {"Problem", "Teams need a faster onboarding path"},
              {"Risks", ""}
            ],
            name: "AI canvas",
            description: "A canvas about onboarding"
          )
      })

    on_exit(fn -> Application.delete_env(:psc, :insights_llm) end)

    %{user: user, scope: Scope.for_user(user), canvas: canvas}
  end

  test "the AI pass appends attributed findings", %{scope: scope, canvas: canvas} do
    Application.put_env(:psc, :insights_llm, fn prompt ->
      assert prompt =~ "AI canvas"
      assert prompt =~ "r1_c1"

      {:ok,
       """
       {"findings":[
         {"kind":"contradiction","severity":"warning","cell_keys":["r1_c1"],
          "field":"content","title":"The problem contradicts the risks",
          "detail":"One cell promises speed while the other warns about cost.","confidence":0.7}
       ]}
       """}
    end)

    {:ok, report} = Insights.run(scope, canvas, canvas.cells)
    assert {:ok, assisted} = Insights.enhance(scope, canvas, canvas.cells, report)

    assert assisted.mode == "assisted"
    assert assisted.provider == "openai"
    assert assisted.model == "gpt-4.1-mini"

    ai = Enum.find(assisted.findings, &(&1["source"] == "ai"))
    assert ai["kind"] == "contradiction"
    assert ai["attribution"]["model"] == "gpt-4.1-mini"
    # The heuristic findings are still there.
    assert Enum.any?(assisted.findings, &(&1["source"] == "heuristic"))
  end

  test "a finding about a cell that does not exist is dropped", %{scope: scope, canvas: canvas} do
    Application.put_env(:psc, :insights_llm, fn _prompt ->
      {:ok,
       ~s({"findings":[{"kind":"contradiction","severity":"warning","cell_keys":["nope"],"title":"Hallucinated","detail":"x"}]})}
    end)

    {:ok, report} = Insights.run(scope, canvas, canvas.cells)
    {:ok, assisted} = Insights.enhance(scope, canvas, canvas.cells, report)

    refute Enum.any?(assisted.findings, &(&1["source"] == "ai"))
  end

  test "a provider failure leaves the heuristic report in place", %{
    scope: scope,
    canvas: canvas
  } do
    Application.put_env(:psc, :insights_llm, fn _prompt -> {:error, "rate limited"} end)

    {:ok, report} = Insights.run(scope, canvas, canvas.cells)
    assert {:error, "rate limited"} = Insights.enhance(scope, canvas, canvas.cells, report)
  end

  describe "parse/2" do
    test "accepts a fenced JSON object and normalises the findings" do
      text = """
      ```json
      {"findings":[
        {"kind":"contradiction","severity":"warning","cell_keys":["r1_c1"],
         "title":"Contradiction","detail":"Details","confidence":0.42},
        {"kind":"not-a-real-kind","title":"Ignored"}
      ]}
      ```
      """

      assert {:ok, [finding]} = LLM.parse(text, %{"provider" => "test"})
      assert finding["kind"] == "contradiction"
      assert finding["source"] == "ai"
      assert finding["confidence"] == 0.42
      assert finding["attribution"]["provider"] == "test"
    end

    test "accepts a bare list" do
      text = ~s([{"kind":"relevance","severity":"info","cell_keys":["r1_c1"],"title":"Drift"}])
      assert {:ok, [%{"kind" => "relevance"}]} = LLM.parse(text, %{})
    end

    test "rejects text that is not JSON" do
      assert {:error, _reason} = LLM.parse("I think the canvas is fine.", %{})
    end

    test "rejects JSON without a findings list" do
      assert {:error, _reason} = LLM.parse(~s({"answer":"ok"}), %{})
    end
  end

  test "the prompt names the canvas, its description and every cell" do
    context = Psc.Insights.Context.new(InsightsFixtures.cells([{"Problem", "Content"}]))

    prompt = LLM.prompt(context)

    assert prompt =~ "Test canvas"
    assert prompt =~ "r1_c1"
    assert prompt =~ "Problem"
    assert prompt =~ ~s("findings")
  end

  test "the prompt includes notes only when they are part of the context" do
    cells = InsightsFixtures.cells([{"Problem", "Content"}])
    without = Psc.Insights.Context.new(cells)

    refute LLM.prompt(without) =~ "The team worries about pricing"

    with_notes =
      Psc.Insights.Context.new(cells,
        notes: [%{"title" => "Scratch", "content" => "The team worries about pricing."}]
      )

    assert LLM.prompt(with_notes) =~ "Scratch"
    assert LLM.prompt(with_notes) =~ "The team worries about pricing."
  end

  test "include_notes reads the canvas notes into the prompt", %{
    scope: scope,
    canvas: canvas,
    user: user
  } do
    note = Psc.NotesFixtures.note_fixture(%{canvas: canvas, user: user, title: "Scratch"})
    {:ok, _} = Psc.Notes.save_content_to_db(note.id, "The team worries about pricing.")

    Application.put_env(:psc, :insights_llm, fn prompt ->
      assert prompt =~ "The team worries about pricing."
      {:ok, ~s({"findings":[]})}
    end)

    {:ok, report} = Insights.run(scope, canvas, canvas.cells)

    assert {:ok, assisted} =
             Insights.enhance(scope, canvas, canvas.cells, report, include_notes: true)

    assert assisted.mode == "assisted"
  end
end
