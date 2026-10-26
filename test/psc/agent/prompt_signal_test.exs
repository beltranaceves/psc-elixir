defmodule Psc.Agent.PromptSignalTest do
  use ExUnit.Case, async: false

  # The per-canvas system prompt is applied through the ReAct strategy's
  # documented command, not through the compile-time agent definition. This is
  # the seam the whole customization feature depends on, so it gets its own
  # regression test.
  test "the ReAct strategy accepts a per-turn system prompt" do
    {:ok, pid} =
      Jido.AgentServer.start_link(
        agent: Psc.Agent.CanvasAgent,
        jido: Psc.Agent.Jido,
        register_global: false
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    signal =
      Jido.Signal.new!("ai.react.set_system_prompt", %{system_prompt: "CUSTOM PROMPT"},
        source: "/test"
      )

    _reply = Jido.AgentServer.call(pid, signal)

    {:ok, server_state} = Jido.AgentServer.state(pid)
    strategy = Jido.Agent.Strategy.State.get(server_state.agent, %{})

    assert strategy[:config][:system_prompt] == "CUSTOM PROMPT"
  end
end
