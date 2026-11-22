defmodule Psc.CanvasBackdropFetchTest do
  use ExUnit.Case, async: true

  alias Psc.Canvas.BackdropFetch

  @public_ip {93, 184, 216, 34}

  defp public_resolver(_host), do: {:ok, [@public_ip]}

  defp fetch(url, plug, resolver \\ &public_resolver/1) do
    BackdropFetch.fetch(url, resolver: resolver, req_options: [plug: plug])
  end

  defp image(conn, body \\ "PNGDATA") do
    conn
    |> Plug.Conn.put_resp_content_type("image/png", nil)
    |> Plug.Conn.send_resp(200, body)
  end

  describe "external?/1" do
    test "only http(s) URLs with a host go through the server" do
      assert BackdropFetch.external?("https://example.com/a.png")
      assert BackdropFetch.external?("http://example.com/a.png")
      refute BackdropFetch.external?("/images/backdrop.png")
      refute BackdropFetch.external?("data:image/png;base64,AAAA")
      refute BackdropFetch.external?(nil)
    end
  end

  describe "public?/1" do
    test "refuses private, loopback, link-local and reserved addresses" do
      for ip <- [
            {127, 0, 0, 1},
            {10, 1, 2, 3},
            {172, 16, 0, 1},
            {172, 31, 255, 255},
            {192, 168, 1, 1},
            {169, 254, 169, 254},
            {100, 64, 0, 1},
            {0, 0, 0, 0},
            {224, 0, 0, 1},
            {0, 0, 0, 0, 0, 0, 0, 1},
            {0xFC00, 0, 0, 0, 0, 0, 0, 1},
            {0xFE80, 0, 0, 0, 0, 0, 0, 1},
            # ::ffff:127.0.0.1
            {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 0x0001}
          ] do
        refute BackdropFetch.public?(ip), "#{inspect(ip)} should not be public"
      end
    end

    test "accepts public addresses" do
      assert BackdropFetch.public?(@public_ip)
      assert BackdropFetch.public?({172, 32, 0, 1})
      assert BackdropFetch.public?({0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111})
    end
  end

  describe "fetch/2" do
    test "returns an image's bytes and content type" do
      assert {:ok, "image/png", "PNGDATA"} = fetch("https://example.com/a.png", &image/1)
    end

    test "refuses a host that resolves to a private address" do
      plug = fn _conn -> flunk("must not be requested") end
      resolver = fn _host -> {:ok, [@public_ip, {10, 0, 0, 5}]} end

      assert {:error, :address} = fetch("https://intranet.example/a.png", plug, resolver)
    end

    test "refuses other schemes and non-default ports" do
      plug = fn _conn -> flunk("must not be requested") end

      assert {:error, :url} = fetch("ftp://example.com/a.png", plug)
      assert {:error, :url} = fetch("file:///etc/passwd", plug)
      assert {:error, :port} = fetch("http://example.com:8080/a.png", plug)
    end

    test "does not follow redirects" do
      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "http://169.254.169.254/")
        |> Plug.Conn.send_resp(302, "")
      end

      assert {:error, :status} = fetch("https://example.com/a.png", plug)
    end

    test "refuses an answer that is not an image" do
      plug = fn conn ->
        conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(200, "<p>")
      end

      assert {:error, :not_image} = fetch("https://example.com/a.png", plug)
    end

    test "stops at the size cap" do
      big = :binary.copy("a", BackdropFetch.max_bytes() + 1)

      assert {:error, :too_large} = fetch("https://example.com/a.png", &image(&1, big))
    end
  end
end
