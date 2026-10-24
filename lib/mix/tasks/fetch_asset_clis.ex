defmodule Mix.Tasks.Psc.FetchAssetClis do
  @shortdoc "Fetches the tailwind/esbuild CLIs that their Mix packages cannot download"

  @moduledoc """
  Pre-fetches the Tailwind and esbuild executables into the paths their Mix
  packages probe, so `mix tailwind` and `mix esbuild` never attempt their own
  download.

  Both packages download with Erlang's `:httpc`, which rejects response headers
  over 10 KB. The GitHub release redirect behind a proxy exceeds that, so a
  proxied build dies with `{:header_too_long, {:max, 10240}}`; esbuild's npm
  registry fetch fails the same way. `:httpc` cannot raise the limit for the
  packages' own request, hence this task: it downloads with `curl` (which
  streams the 100+ MB Tailwind binary to disk) and unpacks the esbuild tarball
  with `:erl_tar`.

  **It needs `curl`.** The Dokploy compose bootstrap installs it, and the
  Dockerfile's builder stage already has it. A host without curl is reported
  plainly rather than worked around — keep the dependency there instead of
  growing this task into a second HTTP client.

  `assets.build` and `assets.deploy` run it, so every build path gets it. It
  no-ops when the binaries are already present, and reports failures rather than
  raising, leaving the packages to produce their own error.
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

  @doc """
  Extracts the executable from an esbuild npm tarball.

  The tarball holds the executable alone: `package/bin/esbuild` on Unix,
  `package/esbuild.exe` on Windows — the same two layouts esbuild's own
  installer reads. `:erl_tar` keeps this independent of the `tar` command.
  """
  def extract_esbuild(tarball) when is_binary(tarball) do
    with {:ok, entries} <- :erl_tar.extract({:binary, tarball}, [:compressed, :memory]) do
      case Enum.find_value(entries, fn {name, contents} ->
             if name in [~c"package/bin/esbuild", ~c"package/esbuild.exe"], do: contents
           end) do
        nil -> {:error, "the esbuild tarball did not contain the executable"}
        binary -> {:ok, binary}
      end
    else
      {:error, reason} -> {:error, "the esbuild tarball could not be read: #{inspect(reason)}"}
    end
  end

  # The package names its binary "esbuild-<target>", which is exactly the npm
  # scope name, so the installed path is the source of truth for the target.
  defp esbuild_target(path) do
    path |> Path.basename() |> String.replace_prefix("esbuild-", "")
  end

  defp install(url, path) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- write(url, path) do
      File.chmod!(path, 0o755)
      report_fetch(path)
    end
  end

  # The esbuild URL is a tarball, so it is fetched whole and unpacked in memory
  # (a few MB) instead of being streamed to its final path.
  defp write(url, path) do
    if String.ends_with?(url, ".tgz") do
      tmp = path <> ".tgz"

      with :ok <- fetch(url, tmp),
           {:ok, binary} <- extract_esbuild(File.read!(tmp)) do
        File.rm(tmp)
        File.write(path, binary)
      end
    else
      fetch(url, path)
    end
  end

  defp fetch(url, path) do
    case System.find_executable("curl") do
      nil ->
        {:error, "curl is not installed, so the CLIs cannot be fetched"}

      exe ->
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
