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

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Some platforms require SSL when connecting to the database, so the
    # application is started when it is there. It is not an error when it is
    # not: a database next to the app is reached in plain text, and the slim
    # Elixir image has no :ssl application at all.
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
