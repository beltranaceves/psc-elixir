defmodule Psc.Agent.ProfileTest do
  use Psc.DataCase, async: true

  alias Psc.Agent.Files
  alias Psc.Agent.Profile
  alias Psc.Agent.Tools

  test "compose keeps the policy first and layers the configured text" do
    prompt =
      Profile.compose(
        "BASE POLICY",
        "Facilitate the canvas.",
        %{"name" => "Critic", "instructions" => "Challenge assumptions."},
        [%{"name" => "brief.md", "description" => "context", "byte_size" => 12}],
        ["read_agent_file"]
      )

    assert String.starts_with?(prompt, "BASE POLICY")
    assert prompt =~ "## Configured instructions"
    assert prompt =~ "## Role: Critic"
    assert prompt =~ "## Reference files"
    assert prompt =~ "brief.md — context (12 bytes)"
    assert prompt =~ "The following files belong to this canvas"
  end

  test "compose returns the base prompt unchanged when nothing is configured" do
    assert Profile.compose("BASE", "", nil, [], Tools.names()) == "BASE"
  end

  test "the file manifest is omitted when the read tool is disabled" do
    prompt =
      Profile.compose(
        "BASE",
        "",
        nil,
        [%{"name" => "brief.md", "byte_size" => 12}],
        ["get_canvas"]
      )

    assert prompt == "BASE"
  end

  test "from_map drops tools that no longer exist and keeps the pinned prompt" do
    profile =
      Profile.from_map(%{
        "canvas_id" => Ecto.UUID.generate(),
        "role" => "critic",
        "role_name" => "Critic",
        "system_prompt" => "PINNED",
        "tools" => ["get_canvas", "removed_tool"],
        "files" => []
      })

    assert profile.system_prompt == "PINNED"
    assert profile.tools == ["get_canvas"]
    assert profile.role == "critic"
  end

  test "for_canvas uses the configured prompt, role and enabled tools" do
    user = Psc.AccountsFixtures.user_fixture()

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{
        "name" => "Profile canvas",
        "cells" => Psc.Canvas.blank_cells(),
        "agent_config" => %{
          "prompt" => "Be brief.",
          "roles" => [
            %{"key" => "critic", "name" => "Critic", "instructions" => "Challenge."}
          ],
          "default_role" => "critic",
          "tools" => ["get_canvas", "read_agent_file"]
        }
      })

    {:ok, :ok} = Files.replace(:canvas, canvas.id, [%{"name" => "brief.md", "content" => "x"}])

    profile = Profile.for_canvas(canvas)

    assert profile.canvas_id == canvas.id
    assert profile.role == "critic"
    assert profile.tools == ["get_canvas", "read_agent_file"]
    assert profile.system_prompt =~ "Be brief."
    assert profile.system_prompt =~ "## Role: Critic"
    assert profile.system_prompt =~ "brief.md"
    assert [%{"name" => "brief.md"}] = profile.files
  end

  test "a legacy enabled: false config no longer disables the agent" do
    user = Psc.AccountsFixtures.user_fixture()

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{
        "name" => "Legacy disabled canvas",
        "cells" => Psc.Canvas.blank_cells(),
        "agent_config" => %{"enabled" => false}
      })

    profile = Profile.for_canvas(canvas)

    assert profile.canvas_id == canvas.id
    assert profile.tools == Tools.names()
  end
end
