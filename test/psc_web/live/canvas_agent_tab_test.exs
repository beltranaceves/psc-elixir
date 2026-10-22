defmodule PscWeb.CanvasAgentTabTest do
  use PscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Psc.Accounts
  alias Psc.Agent
  alias Psc.Agent.Turn
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    # The tab needs a key of the user's own; the model falls back to the
    # deployment alias from config/test.exs.
    {:ok, user} = Accounts.update_agent_key(user, %{"agent_api_key" => "sk-test"})
    %{user: user}
  end

  test "a chat started from the tab receives the turn's events", %{conn: conn, user: user} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    view |> element("button", "Start a chat") |> render_click()

    view
    |> form("#canvas-agent-composer", message: %{content: "hello"})
    |> render_submit()

    # The turn runs in its own process against an unresolvable model; stop it so
    # it cannot outlive the sandbox.
    for pid <- Task.Supervisor.children(Psc.Agent.TurnSupervisor) do
      Task.Supervisor.terminate_child(Psc.Agent.TurnSupervisor, pid)
    end

    # This is the regression: a session created from the tab must be subscribed,
    # or every broadcast below is lost and the bubble stays empty forever.
    assistant =
      Psc.Repo.one(
        from m in Agent.Message,
          where: m.role == :assistant,
          order_by: [desc: m.inserted_at],
          limit: 1
      )

    session = Psc.Repo.get!(Agent.Session, assistant.session_id)

    Phoenix.PubSub.broadcast(
      Psc.PubSub,
      Turn.topic(session.id),
      {:completed, assistant.id, %{content: "hello from pubsub"}}
    )

    assert render(view) =~ "hello from pubsub"
  end

  test "clicking away closes the chat list", %{conn: conn, user: user} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, session} = Agent.create_session(user.id, %{canvas_id: canvas.id})
    {:ok, _} = Agent.append_user_message(session, "chat")

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    view |> element("#canvas-agent-chats") |> render_click()
    assert has_element?(view, "#canvas-agent-chat-list")

    # The browser binding fires this from anywhere outside the wrapper.
    render_click(view, "agent_close_lists", %{})
    refute has_element?(view, "#canvas-agent-chat-list")
  end

  test "the chat list opens, selects and renames", %{conn: conn, user: user} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, first} = Agent.create_session(user.id, %{canvas_id: canvas.id})
    {:ok, _} = Agent.append_user_message(first, "first chat")
    {:ok, second} = Agent.create_session(user.id, %{canvas_id: canvas.id})
    {:ok, _} = Agent.append_user_message(second, "second chat")

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    view |> element("#canvas-agent-chats") |> render_click()
    assert has_element?(view, "#canvas-agent-chat-list")

    view
    |> element(
      ~s|#canvas-agent-chat-list button[phx-click="agent_select"][phx-value-session="#{first.id}"]|
    )
    |> render_click()

    assert has_element?(view, "#canvas-agent-title", "first chat")

    view |> element("#canvas-agent-chats") |> render_click()

    view
    |> element(~s|button[phx-value-session="#{first.id}"][aria-label="Chat options"]|)
    |> render_click()

    assert has_element?(view, ~s|form[id="agent-rename-#{first.id}"]|)

    view
    |> form(~s|form[id="agent-rename-#{first.id}"]|, %{title: "renamed"})
    |> render_submit()

    assert has_element?(view, "#canvas-agent-title", "renamed")
  end
end
