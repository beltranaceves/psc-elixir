defmodule Mix.Tasks.Psc.FetchAssetClisTest do
  # Mutates the packages' application config, so it must not run in parallel.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Psc.FetchAssetClis

  @tailwind_keys [:version, :path]
  @esbuild_keys [:version, :path]

  setup do
    tailwind = Map.new(@tailwind_keys, &{&1, Application.get_env(:tailwind, &1)})
    esbuild = Map.new(@esbuild_keys, &{&1, Application.get_env(:esbuild, &1)})

    on_exit(fn ->
      Enum.each(tailwind, fn {key, value} -> restore(:tailwind, key, value) end)
      Enum.each(esbuild, fn {key, value} -> restore(:esbuild, key, value) end)
    end)

    :ok
  end

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)

  test "the tailwind URL is the release asset for the version and target" do
    assert FetchAssetClis.tailwind_url("4.1.12", "linux-arm64") ==
             "https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.12/tailwindcss-linux-arm64"

    assert FetchAssetClis.tailwind_url("4.1.12", "linux-x64") ==
             "https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.12/tailwindcss-linux-x64"
  end

  test "the esbuild URL is the npm tarball, not a GitHub release asset" do
    assert FetchAssetClis.esbuild_url("linux-x64", "0.25.4") ==
             "https://registry.npmjs.org/@esbuild/linux-x64/-/linux-x64-0.25.4.tgz"
  end

  test "a tailwind binary that is already there is left alone" do
    path = Path.join(System.tmp_dir!(), "fetch-clis-tw-#{System.unique_integer([:positive])}")
    File.write!(path, "fake")
    on_exit(fn -> File.rm(path) end)

    Application.put_env(:tailwind, :version, "4.1.12")
    Application.put_env(:tailwind, :path, path)

    assert {:skip, reason} = FetchAssetClis.ensure_tailwind()
    assert reason =~ "already"
    # Untouched: the task did not try to replace it with a download.
    assert File.read!(path) == "fake"
  end

  test "an esbuild binary that is already there is left alone" do
    path = Path.join(System.tmp_dir!(), "fetch-clis-eb-#{System.unique_integer([:positive])}")
    File.write!(path, "fake")
    on_exit(fn -> File.rm(path) end)

    Application.put_env(:esbuild, :version, "0.25.4")
    Application.put_env(:esbuild, :path, path)

    assert {:skip, reason} = FetchAssetClis.ensure_esbuild()
    assert reason =~ "already"
    assert File.read!(path) == "fake"
  end

  test "an unconfigured version is skipped rather than guessed" do
    Application.delete_env(:tailwind, :version)
    Application.delete_env(:esbuild, :version)

    assert {:skip, "no tailwind version configured"} = FetchAssetClis.ensure_tailwind()
    assert {:skip, "no esbuild version configured"} = FetchAssetClis.ensure_esbuild()
  end
end
