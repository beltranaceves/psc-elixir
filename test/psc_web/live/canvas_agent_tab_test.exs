defmodule PscWeb.CanvasAgentTabTest do
  use PscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Psc.Agent
  alias Psc.Agent.Connections
  alias Psc.Agent.Turn
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  # Sends from the tab start a turn in a supervised task, which cannot be given
  # the `:script` option. The env seam keeps those turns offline.
  setup do
    previous = Application.get_env(:psc, :agent_turn_script)
    Application.put_env(:psc, :agent_turn_script, answer: "scripted answer")
    on_exit(fn -> Application.put_env(:psc, :agent_turn_script, previous) end)
    :ok
  end

  defp create_connection(user, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "name" => "Test",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-test-123"
        },
        attrs
      )

    {:ok, connection} = Connections.create(user, attrs)
    connection
  end

  test "a chat started from the tab receives the turn's events", %{conn: conn, user: user} do
    create_connection(user)
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

  test "a connection saved after the canvas mounted is used without a reload", %{
    conn: conn,
    user: user
  } do
    # A user opens the canvas before adding a connection, then adds one in
    # settings - another tab or another device. The canvas socket still holds
    # the user from mount time, so gating on that struct alone would keep the
    # composer disabled.
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")
    assert render(view) =~ "Add a connection in settings"

    create_connection(user)

    # Coming back to the window after saving in the settings tab refreshes the
    # cached account; without it the composer stays disabled until a reload.
    render_click(view, "agent_refresh", %{})
    refute render(view) =~ "Add a connection in settings"

    view |> element("button", "Start a chat") |> render_click()

    view
    |> form("#canvas-agent-composer", message: %{content: "hello"})
    |> render_submit()

    for pid <- Task.Supervisor.children(Psc.Agent.TurnSupervisor) do
      Task.Supervisor.terminate_child(Psc.Agent.TurnSupervisor, pid)
    end

    refute render(view) =~ "Add a connection in settings"
  end

  test "without a connection the tab says how to add one", %{conn: conn, user: user} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    html = render(view)
    assert html =~ "Add a connection in settings"
    assert has_element?(view, ~s|button[phx-click="agent_new"][disabled]|)
  end

  test "the connection picker pins the chat to another connection", %{conn: conn, user: user} do
    first = create_connection(user, %{"name" => "First"})
    second = create_connection(user, %{"name" => "Second", "model_id" => "gpt-4.1"})

    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, session} = Agent.create_session(user.id, %{canvas_id: canvas.id})

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    # The default is shown until the chat is pinned to another connection.
    assert has_element?(view, "#canvas-agent-connection", first.name)

    view |> element("#canvas-agent-connection") |> render_click()
    assert has_element?(view, "#canvas-agent-connection-list")

    view
    |> element(~s|#canvas-agent-connection-list button[phx-value-connection="#{second.id}"]|)
    |> render_click()

    assert Agent.get_session(session.id, user.id).connection_id == second.id
    assert has_element?(view, "#canvas-agent-connection", second.name)
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

  test "a suggested prompt fills the composer without sending it", %{
    conn: conn,
    user: user
  } do
    create_connection(user)
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, session} = Agent.create_session(user.id, %{canvas_id: canvas.id})

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    view
    |> element(~s|button[phx-click="agent_suggest"][phx-value-prompt="Summarize this canvas"]|)
    |> render_click()

    assert has_element?(view, "#canvas-agent-composer textarea", "Summarize this canvas")
    assert Psc.Agent.list_messages(session) == []
  end

  test "stopping clears the status phase even without a running turn", %{
    conn: conn,
    user: user
  } do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, _session} = Agent.create_session(user.id, %{canvas_id: canvas.id})

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    # A turn's status is broadcast on the session topic; seed one directly so
    # the test does not need a model call.
    send(view.pid, {:status, 1, "waiting for the model…"})
    assert render(view) =~ "waiting for the model…"

    render_click(view, "agent_stop", %{})
    refute render(view) =~ "waiting for the model…"
  end

  test "starting a new chat clears the previous phase", %{conn: conn, user: user} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, _session} = Agent.create_session(user.id, %{canvas_id: canvas.id})

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    send(view.pid, {:status, 1, "running canvas_cell"})
    assert render(view) =~ "running canvas_cell"

    view |> element(~s|button[phx-click="agent_new"]|) |> render_click()

    refute render(view) =~ "running canvas_cell"
  end

  test "stopping cancels the streaming message", %{conn: conn, user: user} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, session} = Agent.create_session(user.id, %{canvas_id: canvas.id})
    {:ok, _user_message} = Agent.append_user_message(session, "hello")
    {:ok, _assistant} = Agent.start_assistant_message(session)

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    # A streaming message is in the transcript; Stop must cancel that row, not
    # put the context's `{:ok, message}` tuple into the list.
    render_click(view, "agent_stop", %{})

    assert render(view) =~ "Stopped."
  end

  # Deltas are broadcast, not persisted until the turn completes. A tab switch
  # must not replace the in-memory transcript with the (still empty) DB row.
  test "switching tabs keeps deltas already streamed into the transcript", %{
    conn: conn,
    user: user
  } do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{"name" => "Agent", "layout_id" => layout.id})

    {:ok, session} = Agent.create_session(user.id, %{canvas_id: canvas.id})
    {:ok, _user_message} = Agent.append_user_message(session, "hello")
    {:ok, assistant} = Agent.start_assistant_message(session)

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")

    Phoenix.PubSub.broadcast(
      Psc.PubSub,
      Turn.topic(session.id),
      {:delta, assistant.id, "partial answer"}
    )

    assert render(view) =~ "partial answer"

    view |> element("#canvas-tab-editor") |> render_click()
    view |> element("#canvas-tab-agent") |> render_click()

    assert render(view) =~ "partial answer"
  end
end
