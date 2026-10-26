defmodule Psc.Agent.CanvasAgentConfigTest do
  use Psc.DataCase, async: true

  alias Psc.Agent.Config
  alias Psc.Agent.Files
  alias Psc.Canvas

  setup do
    user = Psc.AccountsFixtures.user_fixture()
    %{user: user}
  end

  defp template(user, config) do
    {:ok, template} =
      Canvas.create_template(user.id, %{
        "name" => "Agent template #{System.unique_integer([:positive])}",
        "layout_map" => Psc.CanvasFixtures.template_layout_map_fixture(),
        "agent_config" => config
      })

    template
  end

  test "instantiation copies the config and files, and records the source", %{user: user} do
    template =
      template(user, %{
        "prompt" => "Facilitate.",
        "tools" => ["get_canvas"],
        "roles" => [%{"key" => "critic", "name" => "Critic", "instructions" => "Challenge."}],
        "default_role" => "critic"
      })

    {:ok, :ok} =
      Files.replace(:template, template.id, [%{"name" => "brief.md", "content" => "x"}])

    {:ok, canvas} = Canvas.instantiate_template(template, user.id)

    assert canvas.agent_config["prompt"] == "Facilitate."
    assert canvas.source_template_id == template.id
    assert canvas.agent_config_source_hash == Config.hash(template.agent_config)
    assert [file] = Files.list_canvas(canvas.id)
    assert file.name == "brief.md"

    refute Canvas.agent_config_drift?(canvas)
  end

  test "editing the template does not change an existing canvas", %{user: user} do
    template = template(user, %{"prompt" => "Original."})
    {:ok, canvas} = Canvas.instantiate_template(template, user.id)

    {:ok, _template} =
      Canvas.update_template(template, %{"agent_config" => %{"prompt" => "Changed."}})

    assert Canvas.get_unstr_canvas(canvas.id).agent_config["prompt"] == "Original."
    assert Canvas.agent_config_drift?(Canvas.get_unstr_canvas(canvas.id))
  end

  test "reset copies the current template config and files back", %{user: user} do
    template = template(user, %{"prompt" => "Original."})
    {:ok, :ok} = Files.replace(:template, template.id, [%{"name" => "old.md", "content" => "1"}])
    {:ok, canvas} = Canvas.instantiate_template(template, user.id)

    {:ok, :ok} = Files.replace(:template, template.id, [%{"name" => "new.md", "content" => "2"}])

    {:ok, _template} =
      Canvas.update_template(template, %{"agent_config" => %{"prompt" => "Changed."}})

    assert {:ok, reset} = Canvas.reset_agent_config(canvas)
    assert reset.agent_config["prompt"] == "Changed."
    assert [file] = Files.list_canvas(canvas.id)
    assert file.name == "new.md"
    refute Canvas.agent_config_drift?(reset)
  end

  test "a fork copies the config and files", %{user: user} do
    template = template(user, %{"prompt" => "Fork me."})

    {:ok, :ok} =
      Files.replace(:template, template.id, [%{"name" => "brief.md", "content" => "x"}])

    {:ok, fork} = Canvas.fork_template(template, user.id)

    assert fork.agent_config["prompt"] == "Fork me."
    assert [file] = Files.list_template(fork.id)
    assert file.name == "brief.md"
  end

  test "a manual save normalizes the config and replaces the files", %{user: user} do
    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{
        "name" => "Manual",
        "cells" => Canvas.blank_cells()
      })

    {:ok, saved} =
      Canvas.update_agent_config(
        canvas,
        %{"prompt" => "Manual prompt", "tools" => ["get_canvas", "bogus"]},
        [%{"name" => "brief.md", "content" => "x"}]
      )

    assert saved.agent_config["prompt"] == "Manual prompt"
    assert saved.agent_config["tools"] == ["get_canvas"]
    assert [file] = Files.list_canvas(canvas.id)
    assert file.name == "brief.md"
  end
end
