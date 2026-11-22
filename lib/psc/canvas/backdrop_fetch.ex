defmodule Psc.Canvas.BackdropFetch do
  @moduledoc """
  Fetches an image board's backdrop picture on the server, for the PNG/SVG
  export.

  The export draws the board in the browser, and a browser may not read the
  pixels of a picture from another site unless that site allows it (CORS).
  The export route asks the server for the picture instead, so it arrives
  from our own origin.

  Fetching a URL that a user typed is a classic way to make a server reach
  places it should not, so the fetch is narrow on purpose:

    * the caller passes the backdrop URL stored on a canvas the user can
      open — there is no "fetch any URL" entry point;
    * only `http` and `https`, with the default ports;
    * every address the host resolves to must be public: loopback, private,
      link-local, carrier-grade NAT, multicast and reserved ranges are
      refused, for IPv4 and IPv6;
    * no redirects (a redirect could point anywhere), no retries;
    * a short timeout and a size cap, enforced while streaming;
    * the answer must declare an image content type.

  The address is resolved before the request and resolved again by the HTTP
  client, so a host that changes its answer between the two (DNS rebinding)
  is not fully excluded. The other limits keep what such a request could
  return small, short-lived and image-typed.
  """

  import Bitwise

  @max_bytes 10 * 1024 * 1024
  @timeout_ms 8_000

  @doc "The largest picture the export will fetch, in bytes."
  def max_bytes, do: @max_bytes

  @doc """
  Whether the URL points at another site, so the export must fetch it through
  the server. Site paths (`/images/…`) and `data:` URIs are read directly.
  """
  def external?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _other ->
        false
    end
  end

  def external?(_url), do: false

  @doc """
  Fetch the picture at `url`.

  Returns `{:ok, content_type, body}` or `{:error, reason}`. Options (for
  tests): `:resolver` — a `(charlist -> {:ok, [ip_tuple]} | {:error, term})`
  function; `:req_options` — merged into the `Req` call.
  """
  def fetch(url, opts \\ []) do
    config = Application.get_env(:psc, __MODULE__, [])
    resolver = Keyword.get(opts, :resolver, Keyword.get(config, :resolver, &resolve/1))
    req_options = Keyword.get(opts, :req_options, Keyword.get(config, :req_options, []))

    with {:ok, uri} <- parse(url),
         :ok <- check_host(uri.host, resolver) do
      request(uri, req_options)
    end
  end

  defp parse(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if port == URI.default_port(scheme), do: {:ok, uri}, else: {:error, :port}

      _other ->
        {:error, :url}
    end
  end

  defp parse(_url), do: {:error, :url}

  defp check_host(host, resolver) do
    case resolver.(String.to_charlist(host)) do
      {:ok, []} -> {:error, :unresolved}
      {:ok, addresses} -> if Enum.all?(addresses, &public?/1), do: :ok, else: {:error, :address}
      {:error, _reason} -> {:error, :unresolved}
    end
  end

  # Every A and AAAA record. A literal IP parses to itself.
  defp resolve(host) do
    case :inet.parse_address(host) do
      {:ok, ip} ->
        {:ok, [ip]}

      {:error, _} ->
        v4 = addresses(host, :inet)
        v6 = addresses(host, :inet6)
        if v4 == [] and v6 == [], do: {:error, :nxdomain}, else: {:ok, v4 ++ v6}
    end
  end

  defp addresses(host, family) do
    case :inet.getaddrs(host, family) do
      {:ok, list} -> list
      {:error, _} -> []
    end
  end

  @doc false
  # Public unicast only. IPv4-mapped IPv6 addresses are judged as IPv4.
  def public?({a, b, _c, _d}) do
    not (a == 0 or a == 10 or a == 127 or a >= 224 or
           (a == 100 and b >= 64 and b <= 127) or
           (a == 169 and b == 254) or
           (a == 172 and b >= 16 and b <= 31) or
           (a == 192 and b == 168) or
           (a == 192 and b == 0) or
           (a == 198 and (b == 18 or b == 19)))
  end

  def public?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: public?({hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF})

  def public?({a, _, _, _, _, _, _, _} = ip) do
    not (ip == {0, 0, 0, 0, 0, 0, 0, 0} or ip == {0, 0, 0, 0, 0, 0, 0, 1} or
           (a &&& 0xFE00) == 0xFC00 or
           (a &&& 0xFFC0) == 0xFE80 or
           (a &&& 0xFF00) == 0xFF00 or
           (a == 0x2001 and elem(ip, 1) == 0x0DB8))
  end

  def public?(_ip), do: false

  defp request(uri, req_options) do
    options =
      Keyword.merge(
        [
          url: URI.to_string(uri),
          redirect: false,
          retry: false,
          decode_body: false,
          receive_timeout: @timeout_ms,
          connect_options: [timeout: @timeout_ms],
          headers: [{"accept", "image/*"}],
          into: &collect/2
        ],
        req_options
      )

    case Req.get(options) do
      {:ok, %Req.Response{} = resp} -> response(resp)
      {:error, _exception} -> {:error, :fetch}
    end
  end

  # Stream the body and stop as soon as it is too large.
  defp collect({:data, data}, {req, resp}) do
    body = resp.body <> data

    if byte_size(body) > @max_bytes do
      {:halt, {req, %{resp | body: ""} |> Req.Response.put_private(:too_large, true)}}
    else
      {:cont, {req, %{resp | body: body}}}
    end
  end

  defp response(resp) do
    content_type = resp |> Req.Response.get_header("content-type") |> List.first("")

    cond do
      Req.Response.get_private(resp, :too_large) -> {:error, :too_large}
      resp.status not in 200..299 -> {:error, :status}
      not String.starts_with?(String.downcase(content_type), "image/") -> {:error, :not_image}
      true -> {:ok, content_type, resp.body}
    end
  end
end
