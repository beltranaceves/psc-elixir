defmodule PscWeb.ThemeContrastTest do
  @moduledoc """
  Guards light-mode contrast.

  The UI is dark-first, and subtle `white/10` borders and `white/5` surfaces are
  invisible once the light theme renders them on a near-white background. Live
  views must therefore use theme tokens (`base-content/10`, `bg-base-content/5`,
  ...) that invert with the theme. See ADR-015.
  """

  use ExUnit.Case, async: true

  # Hardcoded white/black alpha utilities are theme-blind: white overlays work
  # on the dark theme and disappear on the light one.
  @theme_blind ~r/(?:bg|text|border|ring|divide|outline)-(?:white|black)(?:\/\d+)?/

  test "live views use theme tokens instead of white/black overlays" do
    offenders =
      "lib/psc_web/live/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {line, number} ->
          case Regex.run(@theme_blind, line) do
            [match | _] -> ["#{path}:#{number} → #{match}"]
            _ -> []
          end
        end)
      end)

    assert offenders == [],
           "Use base-content/* theme tokens so light mode keeps contrast:\n" <>
             Enum.join(offenders, "\n")
  end
end
