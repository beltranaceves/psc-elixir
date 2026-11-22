defmodule PscWeb.CanvasExportTest do
  # The backdrop route reads the fetcher's options from the application env.
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  defp image_canvas(user, url) do
    lm = Canvas.image_layout_map() |> put_in(["backdrop", "url"], url)
    template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
    {:ok, canvas} = Canvas.instantiate_template(template, user.id)
    canvas
  end

  defp stub_fetch(plug) do
    previous = Application.get_env(:psc, Psc.Canvas.BackdropFetch)

    Application.put_env(:psc, Psc.Canvas.BackdropFetch,
      resolver: fn _host -> {:ok, [{93, 184, 216, 34}]} end,
      req_options: [plug: plug]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:psc, Psc.Canvas.BackdropFetch, previous),
        else: Application.delete_env(:psc, Psc.Canvas.BackdropFetch)
    end)
  end

  describe "export menu" do
    test "renders the board off screen for the hook, then removes it", %{conn: conn, user: user} do
      lm =
        CanvasFixtures.template_layout_map_fixture()
        |> put_in(["cells", "r1_c1", "hint"], "A hint")

      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(lv, "#export-png")
      assert has_element?(lv, "#export-svg")
      refute has_element?(lv, "#canvas-export")

      lv |> element("#export-png") |> render_click()

      assert has_element?(lv, ~s|#canvas-export[phx-hook="CanvasExport"][data-format="png"]|)
      assert has_element?(lv, ~s|#canvas-export [data-export-sheet][data-mode="table"]|)
      assert has_element?(lv, "#canvas-export h1", template.name)
      # The picture is read-only and has no tooltips.
      refute has_element?(lv, "#canvas-export form")
      refute has_element?(lv, "#canvas-export [data-hint-trigger]")
      # The live board keeps its own.
      assert has_element?(lv, "#hint-cell-r1_c1")

      # A second request while one runs is ignored.
      lv |> element("#export-svg") |> render_click()
      assert has_element?(lv, ~s|#canvas-export[data-format="png"]|)

      render_hook(lv, "export_finished", %{"ok" => true})
      refute has_element?(lv, "#canvas-export")

      lv |> element("#export-svg") |> render_click()
      assert has_element?(lv, ~s|#canvas-export[data-format="svg"]|)

      html = render_hook(lv, "export_finished", %{"ok" => false})
      refute has_element?(lv, "#canvas-export")
      assert html =~ "The export failed"
    end

    test "names the file after the canvas" do
      assert PscWeb.UnstrCanvasLive.Editor.export_filename("Q3 Plan: Café!", "png") ==
               "q3-plan-café.png"

      assert PscWeb.UnstrCanvasLive.Editor.export_filename("  ", "svg") == "canvas.svg"
    end

    test "an external backdrop is drawn through the server; a site path is not", %{
      conn: conn,
      user: user
    } do
      canvas = image_canvas(user, "https://pictures.example.com/map.png")
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      lv |> element("#export-png") |> render_click()

      assert has_element?(lv, ~s|#canvas-export img[src="/canvas/#{canvas.id}/backdrop"]|)
      # The live board still shows the original picture.
      assert has_element?(lv, ~s|#image-board img[src="https://pictures.example.com/map.png"]|)

      local = image_canvas(user, "/images/backdrop.png")
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{local.id}")
      lv |> element("#export-png") |> render_click()

      assert has_element?(lv, ~s|#canvas-export img[src="/images/backdrop.png"]|)
    end
  end

  describe "backdrop route" do
    test "serves the canvas's external backdrop as an inert image", %{conn: conn, user: user} do
      canvas = image_canvas(user, "https://pictures.example.com/map.svg")

      stub_fetch(fn req ->
        assert req.host == "pictures.example.com"
        assert req.request_path == "/map.svg"

        req
        |> Plug.Conn.put_resp_content_type("image/svg+xml", nil)
        |> Plug.Conn.send_resp(200, "<svg/>")
      end)

      conn = get(conn, ~p"/canvas/#{canvas.id}/backdrop")

      assert response(conn, 200) == "<svg/>"
      assert get_resp_header(conn, "content-type") == ["image/svg+xml"]
      assert [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "sandbox"
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "is 502 when the picture cannot be fetched", %{conn: conn, user: user} do
      canvas = image_canvas(user, "https://pictures.example.com/map.png")
      stub_fetch(fn req -> Plug.Conn.send_resp(req, 404, "") end)

      assert conn |> get(~p"/canvas/#{canvas.id}/backdrop") |> response(502)
    end

    test "is 404 for someone without access, or a backdrop that needs no proxy", %{
      conn: conn,
      user: user
    } do
      stub_fetch(fn _req -> flunk("must not fetch") end)

      other = AccountsFixtures.user_fixture()
      foreign = image_canvas(other, "https://pictures.example.com/map.png")
      assert conn |> get(~p"/canvas/#{foreign.id}/backdrop") |> response(404)

      local = image_canvas(user, "/images/backdrop.png")
      assert conn |> get(~p"/canvas/#{local.id}/backdrop") |> response(404)

      assert conn |> get(~p"/canvas/not-a-uuid/backdrop") |> response(404)
    end
  end
end
