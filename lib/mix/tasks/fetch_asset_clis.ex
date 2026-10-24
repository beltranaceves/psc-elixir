defmodule Mix.Tasks.Psc.FetchAssetClis do
  @shortdoc "Fetches the tailwind/esbuild CLIs with curl when Erlang's HTTP client cannot"

  @moduledoc """
  Pre-fetches the Tailwind and esbuild executables that their Mix packages would
  otherwise download with Erlang's `:httpc`.

  `:httpc` rejects response headers longer than 10 KB, and the GitHub release
  redirect that Tailwind's download follows exceeds that behind a proxy, so the
  build dies with `{:header_too_long, {:max, 10240}}`. esbuild's package fetches
  from the npm registry, which fails the same way on a proxied host.

  This task downloads both with `curl` and writes them to the exact paths the
  packages probe (`Tailwind.bin_path/1`, `Esbuild.bin_path/0`), so their
  `install` step finds them and does nothing. It is deliberately
  runner-independent: `mix assets.build` and `mix assets.deploy` call it, so a
  Dockerfile, a compose bootstrap or a buildpack all get the same behaviour
  without having to carry its logic.

  It no-ops when the binaries are already present (including when
  `TAILWIND_PATH` / `ESBUILD_PATH` point at an installed CLI), and a failure is
  reported rather than raised: the packages then attempt their own download and
  produce their usual, more specific error.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    report(ensure_tailwind())
    report(ensure_esbuild())
    :ok
  end

  @doc """
  Fetches the Tailwind CLI unless it is already where the package looks.

  Returns `:ok`, `{:skip, reason}` or `{:error, reason}`.
  """
  def ensure_tailwind do
    case Application.get_env(:tailwind, :version) do
      nil ->
        {:skip, "no tailwind version configured"}

      version ->
        path = Tailwind.bin_path(version)

        if File.exists?(path) do
          {:skip, "tailwind is already at #{Path.relative_to_cwd(path)}"}
        else
          install(tailwind_url(version, Tailwind.configured_target()), path)
        end
    end
  end

  @doc """
  Fetches the esbuild CLI unless it is already where the package looks.
  """
  def ensure_esbuild do
    case Application.get_env(:esbuild, :version) do
      nil ->
        {:skip, "no esbuild version configured"}

      version ->
        path = Esbuild.bin_path()

        if File.exists?(path) do
          {:skip, "esbuild is already at #{Path.relative_to_cwd(path)}"}
        else
          install(esbuild_url(esbuild_target(path), version), path)
        end
    end
  end

  @doc """
  The release URL for a Tailwind version and target (e.g. `"linux-arm64"`).
  """
  def tailwind_url(version, target) do
    Tailwind.default_base_url()
    |> String.replace("$version", version)
    |> String.replace("$target", target)
  end

  @doc """
  The npm tarball URL for an esbuild target (e.g. `"linux-x64"`).

  esbuild publishes its binaries to the npm registry, not as GitHub release
  assets.
  """
  def esbuild_url(target, version) do
    "https://registry.npmjs.org/@esbuild/#{target}/-/#{target}-#{version}.tgz"
  end

  # The package names its binary "esbuild-<target>", which is exactly the npm
  # scope name, so the installed path is the source of truth for the target.
  defp esbuild_target(path) do
    path |> Path.basename() |> String.replace_prefix("esbuild-", "")
  end

  defp install(url, path) do
    if String.ends_with?(url, ".tgz") do
      install_esbuild(url, path)
    else
      install_binary(url, path)
    end
  end

  defp install_binary(url, path) do
    with :ok <- curl(url, path) do
      File.chmod!(path, 0o755)
      report_fetch(path)
    end
  end

  # The tarball holds "package/bin/esbuild"; only the executable is kept.
  defp install_esbuild(url, path) do
    tmp = Path.join(System.tmp_dir!(), "esbuild-cli-#{System.unique_integer([:positive])}")
    tar = tmp <> ".tgz"
    File.mkdir_p!(tmp)

    result =
      with :ok <- curl(url, tar),
           :ok <- untar(tar, tmp),
           :ok <- copy_esbuild(tmp, path) do
        File.chmod!(path, 0o755)
        report_fetch(path)
      end

    File.rm_rf(tmp)
    File.rm(tar)
    result
  end

  # The tarball holds the executable alone: "package/bin/esbuild" on Unix,
  # "package/esbuild.exe" on Windows — the same two layouts esbuild's own
  # installer reads.
  defp copy_esbuild(tmp, path) do
    source =
      ["package/bin/esbuild", "package/esbuild.exe"]
      |> Enum.map(&Path.join(tmp, &1))
      |> Enum.find(&File.exists?/1)

    if source do
      File.mkdir_p!(Path.dirname(path))
      File.cp!(source, path)
      :ok
    else
      {:error, "the esbuild tarball did not contain package/bin/esbuild"}
    end
  end

  defp untar(tar, destination) do
    case System.find_executable("tar") do
      nil ->
        {:error, "tar is not installed"}

      exe ->
        case System.cmd(exe, ["-xzf", tar, "-C", destination], stderr_to_stdout: true) do
          {_out, 0} -> :ok
          {out, code} -> {:error, "tar exited #{code}: #{String.trim(out)}"}
        end
    end
  end

  defp curl(url, path) do
    case System.find_executable("curl") do
      nil ->
        {:error, "curl is not installed"}

      exe ->
        File.mkdir_p!(Path.dirname(path))

        args = ["-fsSL", "--retry", "3", "--retry-delay", "2", "-o", path, url]

        case System.cmd(exe, args, stderr_to_stdout: true) do
          {_out, 0} -> :ok
          {out, code} -> {:error, "curl exited #{code} for #{url}: #{String.trim(out)}"}
        end
    end
  end

  defp report(:ok), do: :ok

  defp report({:skip, _reason}), do: :ok

  defp report({:error, reason}) do
    Mix.shell().info("psc.fetch_asset_clis: #{reason}")
    :ok
  end

  defp report_fetch(path) do
    Mix.shell().info("psc.fetch_asset_clis: fetched #{Path.relative_to_cwd(path)}")
    :ok
  end
end
