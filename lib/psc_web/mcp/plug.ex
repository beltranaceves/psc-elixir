defmodule PscWeb.MCP.Plug do
  @moduledoc """
  A Model Context Protocol endpoint at `/mcp`.

  MCP clients (Claude Desktop, VS Code, Cursor, ...) speak JSON-RPC 2.0 over
  HTTP here: `initialize`, then `tools/list` and `tools/call`. The tools are the
  ones the chat tab uses (`Psc.Agent.Tools`), so the two surfaces cannot drift.

  This is the stateless Streamable HTTP transport: one message per POST, answered
  with JSON. There is no server-initiated stream, so `GET` is a 405 rather than
  an open SSE connection.

  ## Configuration

  The endpoint is disabled (404) unless both variables are set:

    * `PSC_MCP_TOKEN` - the bearer token clients must present.
    * `PSC_MCP_USER` - the email of the account whose scope the tools run with.

  A shared token matches the deployment-configured model of `ADMIN_EMAILS`.
  Per-user tokens (a table, a settings page, revocation) are the upgrade path.
  """

  @behaviour Plug

  import Plug.Conn

  alias Psc.Accounts
  alias Psc.Accounts.Scope
  alias Psc.Accounts.User
  alias Psc.Agent.Tools

  @protocol_versions ["2025-06-18", "2025-03-26"]
  @server_info %{"name" => "psc", "version" => "0.1.0"}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    case service() do
      {:ok, token, email} -> authenticate(conn, token, email)
      :disabled -> conn |> send_resp(404, "") |> halt()
    end
  end

  def call(conn, _opts) do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(405, "")
    |> halt()
  end

  defp service do
    token = System.get_env("PSC_MCP_TOKEN")
    email = System.get_env("PSC_MCP_USER")

    if present?(token) and present?(email) do
      {:ok, token, email |> String.trim() |> String.downcase()}
    else
      :disabled
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp authenticate(conn, token, email) do
    with {:ok, given} <- bearer_token(conn),
         true <- Plug.Crypto.secure_compare(given, token) do
      handle(conn, email)
    else
      _other -> unauthorized(conn)
    end
  end

  defp bearer_token(conn) do
    with [header | _rest] <- get_req_header(conn, "authorization"),
         [scheme, value] <- String.split(header, " ", parts: 2),
         true <- String.downcase(scheme) == "bearer" do
      {:ok, String.trim(value)}
    else
      _other -> :error
    end
  end

  # The endpoint's parser decoded the body before routing, so this reads
  # `body_params` rather than the raw socket.
  defp handle(conn, email) do
    case conn.body_params do
      %{"method" => method} = message when is_binary(method) ->
        dispatch(conn, email, message, method)

      _other ->
        send_json(conn, 400, rpc_error(nil, -32700, "Parse error"))
    end
  end

  # A message without an id is a notification: the protocol forbids replying.
  defp dispatch(conn, _email, message, _method) when not is_map_key(message, "id") do
    conn |> send_resp(202, "") |> halt()
  end

  defp dispatch(conn, email, message, method) do
    case method do
      "initialize" -> reply(conn, message, initialize(message))
      "ping" -> reply(conn, message, {:ok, %{}})
      "tools/list" -> reply(conn, message, {:ok, %{"tools" => Tools.mcp_specs()}})
      "tools/call" -> reply(conn, message, call_tool(message, email))
      _other -> reply(conn, message, {:error, -32601, "Method not found: #{method}"})
    end
  end

  defp initialize(message) do
    requested = get_in(message, ["params", "protocolVersion"])
    version = if requested in @protocol_versions, do: requested, else: hd(@protocol_versions)

    {:ok,
     %{
       "protocolVersion" => version,
       "capabilities" => %{"tools" => %{"listChanged" => false}},
       "serverInfo" => @server_info
     }}
  end

  defp call_tool(%{"params" => %{"name" => name} = params}, email) when is_binary(name) do
    arguments =
      case params["arguments"] do
        %{} = arguments -> arguments
        _other -> %{}
      end

    with {:ok, scope} <- scope_for(email) do
      case Tools.fetch(name) do
        nil ->
          {:error, -32602, "Unknown tool: #{name}"}

        tool ->
          # Run through Jido.Exec so the action's schema validates and coerces
          # the arguments before `run/2` sees them. Exec expects atom keys, and
          # JSON arrives with strings; only atoms the VM already knows are
          # converted, so a stray key stays a string and fails validation.
          case Jido.Exec.run(tool, atomize(arguments), %{scope: scope}) do
            {:ok, value} -> {:ok, tool_result(value, false)}
            {:error, reason} -> {:ok, tool_result(error_text(reason), true)}
            other -> {:error, -32603, "The tool returned #{inspect(other)}"}
          end
      end
    else
      {:error, reason} -> {:error, -32603, reason}
    end
  end

  defp call_tool(_message, _email), do: {:error, -32602, "params.name is required"}

  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(%{__exception__: true} = reason), do: Exception.message(reason)
  defp error_text(reason), do: inspect(reason)

  defp atomize(arguments) do
    Map.new(arguments, fn
      {key, value} when is_binary(key) -> {existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp scope_for(email) do
    case Accounts.get_user_by_email(email) do
      %User{} = user -> {:ok, Scope.for_user(user)}
      nil -> {:error, "MCP is not configured: PSC_MCP_USER has no account."}
    end
  end

  defp tool_result(value, is_error) do
    text =
      case value do
        text when is_binary(text) -> text
        other -> Jason.encode!(other, pretty: true)
      end

    result = %{"content" => [%{"type" => "text", "text" => text}], "isError" => is_error}

    # Structured results let capable clients skip parsing the text block.
    if is_map(value) and not is_error do
      Map.put(result, "structuredContent", value)
    else
      result
    end
  end

  defp reply(conn, message, {:ok, result}) do
    send_json(conn, 200, %{"jsonrpc" => "2.0", "id" => message["id"], "result" => result})
  end

  defp reply(conn, message, {:error, code, text}) do
    send_json(conn, 200, %{
      "jsonrpc" => "2.0",
      "id" => message["id"],
      "error" => %{"code" => code, "message" => text}
    })
  end

  defp rpc_error(id, code, text) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => text}}
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> send_resp(401, "")
    |> halt()
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, Jason.encode!(payload))
    |> halt()
  end
end
