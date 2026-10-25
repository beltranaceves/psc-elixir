defmodule PscWeb.EndpointStaticTest do
  # Writes temporary digested files into the build's priv/static, so it must not
  # run in parallel with other request tests.
  use PscWeb.ConnCase, async: false

  @digest "0123456789abcdef0123456789abcdef"

  setup do
    static_dir = Application.app_dir(:psc, "priv/static")
    File.mkdir_p!(static_dir)

    for {name, body} <- digested_files() do
      path = Path.join(static_dir, name)
      File.write!(path, body)
      on_exit(fn -> File.rm(path) end)
    end

    :ok
  end

  # Verified routes rewrite these links to their digested names in production;
  # Plug.Static has to serve them or the manifest 404s and the app cannot be
  # installed as a PWA.
  test "serves the digested root-level assets", %{conn: conn} do
    for {name, _body} <- digested_files() do
      conn = get(conn, "/" <> name)
      assert conn.status == 200, "expected #{name} to be served, got #{conn.status}"
    end
  end

  test "still serves the undigested root-level files", %{conn: conn} do
    for path <- ~w(/manifest.webmanifest /sw.js /offline.html) do
      assert get(conn, path).status == 200, "expected #{path} to be served"
    end
  end

  defp digested_files do
    [
      {"manifest-#{@digest}.webmanifest", "{}"},
      {"sw-#{@digest}.js", "// service worker"}
    ]
  end
end
