defmodule Psc.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :psc

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Everything a boot needs, in one release command: migrate, bootstrap the
  admins configured in `ADMIN_EMAILS`, and seed the built-in templates.
  """
  def setup do
    migrate()
    bootstrap_admins()
    seed_builtin_templates()
  end

  @doc """
  Promotes (or creates) the admins listed in `ADMIN_EMAILS`.
  """
  def bootstrap_admins do
    load_app()
    run_with_repo(&Psc.Accounts.bootstrap_admins/0)
  end

  @doc """
  Creates any missing built-in template.
  """
  def seed_builtin_templates do
    load_app()
    run_with_repo(&Psc.Canvas.seed_builtin_templates/0)
  end

  defp run_with_repo(fun) do
    Enum.map(repos(), fn repo ->
      {:ok, _pid, result} = Ecto.Migrator.with_repo(repo, fn _repo -> fun.() end)
      result
    end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_loaded(@app)

    # Some platforms require SSL when connecting to the database. Do not start
    # it for a plain-text database: OTP loads the system trust store while
    # starting TLS, which is unnecessary for a database next to the app.
    if repo_uses_ssl?() do
      Application.ensure_all_started(:ssl)
    end
  end

  defp repo_uses_ssl? do
    @app
    |> Application.get_env(Psc.Repo, [])
    |> Keyword.get(:ssl)
    |> then(&(&1 not in [nil, false]))
  end
end
