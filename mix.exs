defmodule Psc.MixProject do
  use Mix.Project

  def project do
    [
      app: :psc,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Psc.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, verify: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:delta_crdt, "~> 0.6.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:earmark, "~> 1.4"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:mishka_chelekom, "~> 0.0.8", only: :dev},
      {:justify, "~> 1.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "deps.compile", "nif.fix", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "nif.fix": &fix_nif_extensions/1,
      "e2e.setup": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "run priv/repo/e2e_seeds.exs",
        "assets.build"
      ],
      test: ["nif.fix", "ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind psc", "esbuild psc"],
      "assets.deploy": [
        "tailwind psc --minify",
        "esbuild psc --minify",
        "phx.digest"
      ],
      # Fast agent/developer loop: format, fail on warnings, stop at the first
      # test failure. Self-healing — `format` rewrites files in place.
      verify: ["nif.fix", "format", "compile --warnings-as-errors", "test --max-failures 1"],
      # Strict full check: formatting must already be applied (no side effects).
      precommit: [
        "nif.fix",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "test"
      ]
    ]
  end

  # On Windows, Erlang resolves NIFs as `.dll`, but `elixir_make` builds them as `.so`
  # (it uses the dependency's Unix `Makefile`, which hardcodes the `.so` name).
  # Elixir/Erlang then fails with a misleading "module could not be found" error.
  #
  # This makes each build environment self-healing by copying any `priv/*.so` that has
  # no matching `.dll`. No-op on non-Windows platforms and when already fixed.
  defp fix_nif_extensions(_args) do
    if match?({:win32, _}, :os.type()) do
      lib_dir = Path.join(Mix.Project.build_path(), "lib")

      for priv <- Path.wildcard(Path.join(lib_dir, "*/priv")),
          so <- Path.wildcard(Path.join(priv, "*.so")),
          dll = Path.rootname(so) <> ".dll",
          not File.exists?(dll) do
        File.cp!(so, dll)
        Mix.shell().info("nif.fix: created #{Path.relative_to_cwd(dll)}")
      end
    end

    :ok
  end
end
