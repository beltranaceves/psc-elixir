defmodule PscWeb.PWATest do
  use PscWeb.ConnCase, async: true

  test "serves an installable web app manifest", %{conn: conn} do
    body = conn |> get(~p"/manifest.webmanifest") |> response(200)

    assert %{
             "short_name" => "PSC",
             "start_url" => "/canvas",
             "scope" => "/",
             "display" => "standalone",
             "icons" => icons
           } = Jason.decode!(body)

    assert Enum.any?(icons, &(&1["sizes"] == "192x192" and &1["purpose"] == "any"))
    assert Enum.any?(icons, &(&1["sizes"] == "512x512" and &1["purpose"] == "any"))
    assert Enum.any?(icons, &(&1["sizes"] == "192x192" and &1["purpose"] == "maskable"))
    assert Enum.any?(icons, &(&1["sizes"] == "512x512" and &1["purpose"] == "maskable"))
  end

  test "serves the service worker from the root scope", %{conn: conn} do
    body = conn |> get(~p"/sw.js") |> response(200)

    # It must live at the root: a worker served under /assets would only
    # control /assets, never the app.
    assert body =~ ~s("/offline.html")
    assert body =~ "self.skipWaiting()"
    assert body =~ "networkFirstNavigation"
  end

  test "serves the offline fallback page", %{conn: conn} do
    assert conn |> get(~p"/offline.html") |> response(200) =~ "You're offline"
  end

  test "serves the generated icons", %{conn: conn} do
    for path <- [
          ~p"/images/icon-192.png",
          ~p"/images/icon-512.png",
          ~p"/images/icon-maskable-512.png",
          ~p"/images/apple-touch-icon.png"
        ] do
      assert conn |> get(path) |> response(200) |> byte_size() > 0
    end
  end

  test "the root layout advertises the app", %{conn: conn} do
    html = conn |> get(~p"/users/log-in") |> html_response(200)

    assert html =~ ~s(rel="manifest")
    assert html =~ "/manifest.webmanifest"
    assert html =~ "apple-touch-icon"
    assert html =~ ~s(name="theme-color")
    assert html =~ ~s(name="apple-mobile-web-app-title" content="PSC")
  end
end
