defmodule Mix.Tasks.NifFix do
  @moduledoc """
  Ensures Windows NIF `.dll` files exist next to their `.so` counterparts.

  Erlang on Windows resolves NIFs as `.dll`, but `elixir_make` builds them from
  the dependency's Unix `Makefile`, which hardcodes the `.so` name. Without the
  `.dll`, modules like `Bcrypt.Base` fail to load with a misleading "make sure
  you have a C compiler" error.

  Runs as part of the `compilers` list in `mix.exs`, so it heals every build
  environment (`dev`, `test`, `prod`) after every compilation — no alias, no
  env, and no ordering issue can produce a missing `.dll` again. No-op on
  non-Windows platforms and when already fixed.
  """
  use Mix.Task.Compiler

  @impl Mix.Task.Compiler
  def run(_args) do
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
