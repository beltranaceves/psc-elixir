import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/psc start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :psc, PscWeb.Endpoint, server: true
end

# The HTTP port is resolved at runtime so the same build can be started on a
# different port. `PSC_PORT` (project-namespaced) takes precedence over `PORT`
# (the deployment convention), falling back to 4000. The E2E harness in
# `test/e2e/` relies on this to run alongside a dev server.
#
# Port resolution: only NUMERIC values of `PSC_PORT`/`PORT` are honored,
# anything else falls back to 4000 — the port Gigalixir's health checks and
# proxy expect (their runner also injects `PSC_PORT`/`PORT` as URLs like
# "tcp://10.x.x.x:80"; `PSC_PORT` collides with our app-name-derived var
# and our E2E harness uses it as a numeric override).
port_from_env = System.get_env("PSC_PORT") || System.get_env("PORT", "")

endpoint_port =
  if Regex.match?(~r/^\d+$/, port_from_env) do
    String.to_integer(port_from_env)
  else
    4000
  end

config :psc, PscWeb.Endpoint,
  http: [
    port: endpoint_port
  ]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :psc, Psc.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The database connection's SSL.
  #
  # It is not a universal yes: Gigalixir's managed Postgres *requires* it,
  # while a Postgres container next to the app usually does not offer it (and
  # the slim Elixir image has no :ssl application at all - the connection dies
  # with "ssl not available"). The host decides by default: a database on the
  # same machine or a private network is reached in plain text, anything else
  # is encrypted. `PSC_DB_SSL=true|false` overrides the decision.
  #
  # A bare host without a dot is a compose service ("postgres", "db") or a
  # container name - a public hostname always has a dot in it - and the private
  # address ranges are the ones a local network uses.
  database_host =
    case URI.parse(database_url) do
      %URI{host: host} when is_binary(host) -> host
      _other -> ""
    end

  private_address? =
    case database_host |> String.split(".") |> Enum.map(&Integer.parse/1) do
      [{10, ""}, _, _, _] -> true
      [{172, ""}, {second, ""}, _, _] when second in 16..31 -> true
      [{192, ""}, {168, ""}, _, _] -> true
      _other -> false
    end

  local_database? =
    database_host in ["", "localhost", "127.0.0.1", "::1"] or
      not String.contains?(database_host, ".") or
      private_address?

  database_ssl? =
    case System.get_env("PSC_DB_SSL") do
      "true" -> true
      "false" -> false
      _otherwise -> not local_database?
    end

  # Certificate verification is relaxed for the free-tier demo; switch to
  # verify_peer + cacerts for a production database (see the Postgrex docs).
  if database_ssl? do
    config :psc, Psc.Repo, ssl: [verify: :verify_none]
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  # The agent tab needs a model spec ("provider:model") and the provider's key.
  # Without AGENT_MODEL the tab stays off rather than failing on first use.
  case System.get_env("AGENT_MODEL") do
    nil ->
      config :psc, :agent_enabled, false

    model ->
      config :jido_ai, model_aliases: %{default: model, fast: model}
      config :psc, :agent_enabled, true
  end

  config :psc, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # The public URL Phoenix generates (redirects, emails). It is the URL of the
  # proxy in front of the app, not the app's own port: Gigalixir and a
  # Dokploy/Traefik setup both terminate TLS on 443, and a deployment serving
  # plain HTTP on a port of its own sets `PSC_URL_SCHEME` and `PSC_URL_PORT`.
  url_scheme = System.get_env("PSC_URL_SCHEME", "https")

  url_port =
    case System.get_env("PSC_URL_PORT") do
      nil ->
        443

      port ->
        case Integer.parse(port) do
          {number, ""} -> number
          _other -> 443
        end
    end

  config :psc, PscWeb.Endpoint,
    url: [
      host: host,
      port: url_port,
      scheme: url_scheme
    ],
    http: [
      ip: {0, 0, 0, 0},
      port: endpoint_port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :psc, PscWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :psc, PscWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :psc, Psc.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
