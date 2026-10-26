defmodule Psc.Agent.ConfigTest do
  use ExUnit.Case, async: true

  alias Psc.Agent.Config
  alias Psc.Agent.Tools

  test "an empty config normalizes to the defaults" do
    assert Config.normalize(nil) == Config.default()
    assert Config.normalize(%{}) == Config.default()
    # The old on/off switch is gone; a legacy key is not carried forward.
    refute Map.has_key?(Config.normalize(%{"enabled" => false}), "enabled")
  end

  test "unknown tools are dropped and the full set compacts to nil" do
    assert Config.normalize(%{"tools" => ["get_canvas", "not_a_tool"]})["tools"] == [
             "get_canvas"
           ]

    assert Config.normalize(%{"tools" => Tools.names()})["tools"] == nil
    assert Config.enabled_tool_names(%{"tools" => nil}) == Tools.names()
    assert Config.normalize(%{"tools" => []})["tools"] == []
    assert Config.enabled_tool_names(%{"tools" => []}) == []
  end

  test "text is clipped and control characters are removed" do
    config = Config.normalize(%{"prompt" => String.duplicate("x", 9_000) <> <<0>>})

    assert String.length(config["prompt"]) == 8_000
    refute config["prompt"] =~ <<0>>
  end

  test "role keys are unique and the default role is repaired" do
    config =
      Config.normalize(%{
        "roles" => [
          %{"name" => "Facilitator", "instructions" => "Keep moving"},
          %{"name" => "Facilitator", "instructions" => "Challenge"},
          %{"name" => "", "instructions" => ""}
        ],
        "default_role" => "missing"
      })

    assert Enum.map(config["roles"], & &1["key"]) == ["facilitator", "facilitator-2"]
    assert config["default_role"] == "facilitator"
  end

  test "draft helpers keep role keys stable while editing" do
    config = Config.default() |> Config.add_role()
    [role] = config["roles"]
    key = role["key"]

    config = Config.put_role_field(config, key, "name", "Critic")
    config = Config.put_role_field(config, key, "instructions", "Challenge assumptions")
    config = Config.set_default_role(config, key)

    assert [%{"key" => ^key, "name" => "Critic", "instructions" => "Challenge assumptions"}] =
             config["roles"]

    assert config["default_role"] == key

    config = Config.remove_role(config, key)
    assert config["roles"] == []
    assert config["default_role"] == nil
  end

  test "toggle_tool removes and restores tools, collapsing the full set" do
    config = Config.default()
    assert Config.tool_enabled?(config, "get_canvas")

    config = Config.toggle_tool(config, "get_canvas")
    refute Config.tool_enabled?(config, "get_canvas")
    assert "get_canvas" not in Config.enabled_tool_names(config)

    config = Config.toggle_tool(config, "get_canvas")
    assert Config.tool_enabled?(config, "get_canvas")
    assert config["tools"] == nil
  end

  test "apply_form_change updates the field named by the form target" do
    config = Config.default()

    config =
      Config.apply_form_change(config, ["agent_prompt"], %{"agent_prompt" => "Be brief."})

    config = Config.add_role(config)
    [role] = config["roles"]

    config =
      Config.apply_form_change(
        config,
        ["role", role["key"], "name"],
        %{"role" => %{role["key"] => %{"name" => "Critic"}}}
      )

    assert config["prompt"] == "Be brief."
    assert hd(config["roles"])["name"] == "Critic"
  end

  test "the hash is stable across equivalent configs" do
    a = Config.hash(%{"prompt" => "hello", "roles" => []})
    b = Config.hash(%{"prompt" => "hello"})
    c = Config.hash(%{"prompt" => "different"})

    assert a == b
    refute a == c
  end
end
