defmodule PscWeb.AgentConfigLiveTest do
  use PscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Psc.Agent
  alias Psc.Agent.Connections
  alias Psc.Agent.Files
  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:psc, :agent_turn_script)
    Application.put_env(:psc, :agent_turn_script, answer: "scripted answer")
    on_exit(fn -> Application.put_env(:psc, :agent_turn_script, previous) end)
    :ok
  end

  defp create_connection(user) do
    {:ok, _connection} =
      Connections.create(user, %{
        "name" => "Test",
        "provider" => "openai",
        "model_id" => "gpt-4.1-mini",
        "api_key" => "sk-test-123"
      })

    :ok
  end

  defp stop_turns do
    for pid <- Task.Supervisor.children(Psc.Agent.TurnSupervisor) do
      Task.Supervisor.terminate_child(Psc.Agent.TurnSupervisor, pid)
    end
  end

  test "the template designer saves the agent section and its files", %{
    conn: conn,
    user: user
  } do
    template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")

    assert has_element?(lv, "#template-agent-prompt")
    assert has_element?(lv, "#template-agent-tool-get_canvas")

    lv
    |> form("#template-agent-config")
    |> render_change(%{
      "_target" => ["agent_prompt"],
      "agent_prompt" => "Facilitate the canvas."
    })

    # Disable one tool, leaving the rest enabled.
    lv |> element("#template-agent-tool-get_canvas") |> render_click()

    lv |> element("#template-agent-add-role") |> render_click()

    lv
    |> form("#template-agent-config")
    |> render_change(%{
      "_target" => ["role", "role", "name"],
      "role" => %{"role" => %{"name" => "Critic"}}
    })

    lv
    |> form("#template-agent-config")
    |> render_change(%{
      "_target" => ["role", "role", "instructions"],
      "role" => %{"role" => %{"instructions" => "Challenge assumptions."}}
    })

    lv
    |> element("#template-agent-role-role button[phx-click='agent_cfg_set_default_role']")
    |> render_click()

    lv |> element("#template-agent-add-file") |> render_click()

    lv
    |> form("#template-agent-config")
    |> render_change(%{
      "_target" => ["file", "0", "path"],
      "file" => %{"0" => %{"path" => "docs/brief.md"}}
    })

    lv
    |> form("#template-agent-config")
    |> render_change(%{
      "_target" => ["file", "0", "content"],
      "file" => %{"0" => %{"content" => "Reference context"}}
    })

    assert {:error, {:redirect, %{to: "/templates"}}} =
             lv
             |> form("#template-form", %{
               "name" => template.name,
               "description" => "Saved with an agent"
             })
             |> render_submit()

    saved = Canvas.get_template_with_author(template.id)

    assert saved.agent_config["prompt"] == "Facilitate the canvas."
    assert "get_canvas" not in saved.agent_config["tools"]

    assert [%{"key" => "role", "name" => "Critic", "instructions" => "Challenge assumptions."}] =
             saved.agent_config["roles"]

    assert saved.agent_config["default_role"] == "role"

    assert [file] = Files.list_template(template.id)
    assert file.path == "docs/brief.md"
    assert file.name == "brief.md"
    assert file.content == "Reference context"
  end

  test "the canvas Info tab saves and resets the agent section", %{conn: conn, user: user} do
    template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, template} =
      Canvas.update_template(template, %{
        "agent_config" => %{
          "prompt" => "Template prompt",
          "roles" => [%{"key" => "critic", "name" => "Critic", "instructions" => "Challenge."}],
          "default_role" => "critic"
        }
      })

    {:ok, :ok} =
      Files.replace(:template, template.id, [%{"name" => "brief.md", "content" => "v1"}])

    {:ok, canvas} = Canvas.instantiate_template(template, user.id)

    {:ok, lv, html} = live(conn, ~p"/canvas/#{canvas.id}?tab=info")

    assert html =~ "Agent"
    assert has_element?(lv, "#canvas-agent-prompt")
    refute has_element?(lv, "#canvas-agent-enabled")
    assert has_element?(lv, "#canvas-agent-reset")
    assert render(lv) =~ "Template prompt"
    assert render(lv) =~ "brief.md"

    lv
    |> form("#canvas-agent-config")
    |> render_change(%{
      "_target" => ["agent_prompt"],
      "agent_prompt" => "Canvas prompt"
    })

    lv |> element("#canvas-agent-save") |> render_click()

    saved = Canvas.get_unstr_canvas(canvas.id)
    assert saved.agent_config["prompt"] == "Canvas prompt"

    # The template moved on. The canvas is stale until reset.
    {:ok, _template} =
      Canvas.update_template(template, %{"agent_config" => %{"prompt" => "Template v2"}})

    assert Canvas.agent_config_drift?(Canvas.get_unstr_canvas(canvas.id))

    lv |> element("#canvas-agent-reset") |> render_click()

    reset = Canvas.get_unstr_canvas(canvas.id)
    assert reset.agent_config["prompt"] == "Template v2"
    refute Canvas.agent_config_drift?(reset)
  end

  test "an uploaded file is added to the draft and saved with the template", %{
    conn: conn,
    user: user
  } do
    template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")

    upload =
      file_input(lv, "#template-agent-config", :agent_files, [
        %{name: "brief.md", content: "Context from a folder"}
      ])

    render_upload(upload, "brief.md")
    lv |> element("#template-agent-upload-submit") |> render_click()

    assert has_element?(lv, "#template-agent-file-0-path")
    refute has_element?(lv, "#template-agent-file-0[open]")

    assert {:error, {:redirect, %{to: "/templates"}}} =
             lv
             |> form("#template-form", %{
               "name" => template.name,
               "description" => "Saved with an upload"
             })
             |> render_submit()

    assert [file] = Files.list_template(template.id)
    assert file.path == "brief.md"
    assert file.name == "brief.md"
    assert file.content == "Context from a folder"
  end

  test "the upload preview shows the tree and removes a whole directory", %{
    conn: conn,
    user: user
  } do
    template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")

    upload =
      file_input(lv, "#template-agent-config", :agent_folder, [
        %{name: "README.md", content: "root"},
        %{name: "docs/brief.md", content: "brief"},
        %{name: "docs/spec/bento.md", content: "bento"}
      ])

    render_upload(upload, "README.md")
    render_upload(upload, "docs/brief.md")
    render_upload(upload, "docs/spec/bento.md")

    html = render(lv)
    assert html =~ "README.md"
    assert html =~ "docs/"
    assert html =~ "bento.md"

    lv
    |> element(~s|#template-agent-upload-preview button[aria-label="Remove docs"]|)
    |> render_click()

    html = render(lv)
    assert html =~ "README.md"
    refute html =~ "brief.md"
    refute html =~ "bento.md"

    lv |> element("#template-agent-upload-submit") |> render_click()

    assert {:error, {:redirect, %{to: "/templates"}}} =
             lv
             |> form("#template-form", %{
               "name" => template.name,
               "description" => "Saved from a preview"
             })
             |> render_submit()

    assert [file] = Files.list_template(template.id)
    assert file.path == "README.md"
    assert file.content == "root"
  end

  test "the role picker pins the role on the first message", %{conn: conn, user: user} do
    create_connection(user)

    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{
        "name" => "Roles",
        "cells" => Canvas.blank_cells(),
        "agent_config" => %{
          "prompt" => "Pick a role.",
          "roles" => [
            %{"key" => "facilitator", "name" => "Facilitator", "instructions" => "Guide."},
            %{"key" => "critic", "name" => "Critic", "instructions" => "Challenge."}
          ],
          "default_role" => "facilitator"
        }
      })

    {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    lv |> element("button", "Start a chat") |> render_click()

    assert has_element?(lv, "#canvas-agent-role")

    lv |> element("#canvas-agent-role") |> render_change(%{"role" => "critic"})

    lv
    |> form("#canvas-agent-composer", message: %{content: "hello"})
    |> render_submit()

    stop_turns()

    session =
      Psc.Repo.one!(
        from s in Agent.Session,
          where: s.canvas_id == ^canvas.id,
          order_by: [desc: s.inserted_at],
          limit: 1
      )

    assert session.role == "critic"
    assert session.profile["role"] == "critic"
    assert session.profile["system_prompt"] =~ "## Role: Critic"
  end
end
