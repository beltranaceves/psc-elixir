defmodule PscWeb.MCP.PlugTest do
  # Env vars are process-global, so this file cannot run concurrently.
  use PscWeb.ConnCase, async: false

  alias Psc.AccountsFixtures
  alias Psc.NotesFixtures

  @token "test-mcp-token"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    System.put_env("PSC_MCP_TOKEN", @token)
    System.put_env("PSC_MCP_USER", user.email)

    on_exit(fn ->
      System.delete_env("PSC_MCP_TOKEN")
      System.delete_env("PSC_MCP_USER")
    end)

    %{conn: conn, user: user}
  end

  defp rpc(conn, message, token \\ @token) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> post("/mcp", Jason.encode!(message))
  end

  test "initialize negotiates the protocol version", %{conn: conn} do
    response =
      conn
      |> rpc(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2025-06-18"}
      })
      |> json_response(200)

    assert response["id"] == 1
    assert response["result"]["protocolVersion"] == "2025-06-18"
    assert response["result"]["capabilities"]["tools"]
    assert response["result"]["serverInfo"]["name"] == "psc"
  end

  test "an unknown protocol version falls back to the newest we speak", %{conn: conn} do
    response =
      conn
      |> rpc(%{
        "jsonrpc" => "2.0",
        "id" => "a",
        "method" => "initialize",
        "params" => %{"protocolVersion" => "1999-01-01"}
      })
      |> json_response(200)

    assert response["result"]["protocolVersion"] == "2025-06-18"
  end

  test "notifications are acknowledged without a body", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> put_req_header("content-type", "application/json")
      |> post(
        "/mcp",
        Jason.encode!(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
      )

    assert response(conn, 202) == ""
  end

  test "tools/list exposes the same tools as the chat", %{conn: conn} do
    response =
      conn
      |> rpc(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})
      |> json_response(200)

    names = Enum.map(response["result"]["tools"], & &1["name"])

    assert names == Enum.map(Psc.Agent.Tools.all(), & &1.name())
    assert Enum.all?(response["result"]["tools"], &(&1["inputSchema"]["type"] == "object"))
  end

  test "tools/call runs a read-only tool with the configured user's scope", %{
    conn: conn,
    user: user
  } do
    NotesFixtures.canvas_fixture(%{:user => user, "name" => "Q3 Planning"})

    response =
      conn
      |> rpc(%{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{"name" => "list_canvases", "arguments" => %{}}
      })
      |> json_response(200)

    assert response["result"]["isError"] == false
    assert [%{"type" => "text", "text" => text}] = response["result"]["content"]
    assert text =~ "Q3 Planning"

    assert response["result"]["structuredContent"]["canvases"] |> hd() |> Map.get("name") ==
             "Q3 Planning"
  end

  test "a tool that refuses surfaces isError rather than a protocol error", %{conn: conn} do
    response =
      conn
      |> rpc(%{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{"name" => "get_canvas", "arguments" => %{"id" => Ecto.UUID.generate()}}
      })
      |> json_response(200)

    assert response["result"]["isError"] == true
    assert hd(response["result"]["content"])["text"] =~ "No canvas"
  end

  test "an unknown tool is a protocol error", %{conn: conn} do
    response =
      conn
      |> rpc(%{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "delete_everything", "arguments" => %{}}
      })
      |> json_response(200)

    assert response["error"]["code"] == -32602
  end

  test "an unknown method is a protocol error", %{conn: conn} do
    response =
      conn
      |> rpc(%{"jsonrpc" => "2.0", "id" => 6, "method" => "resources/list"})
      |> json_response(200)

    assert response["error"]["code"] == -32601
  end

  test "a missing or wrong bearer token is rejected", %{conn: conn} do
    message = %{"jsonrpc" => "2.0", "id" => 7, "method" => "tools/list"}

    conn |> rpc(message, "wrong") |> response(401)

    conn
    |> put_req_header("content-type", "application/json")
    |> post("/mcp", Jason.encode!(message))
    |> response(401)
  end

  test "GET is not part of the stateless transport", %{conn: conn} do
    conn
    |> put_req_header("authorization", "Bearer #{@token}")
    |> get("/mcp")
    |> response(405)
  end

  test "the endpoint 404s when it is not configured", %{conn: conn} do
    System.delete_env("PSC_MCP_TOKEN")

    conn
    |> rpc(%{"jsonrpc" => "2.0", "id" => 8, "method" => "tools/list"})
    |> response(404)
  end
end
