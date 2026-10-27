defmodule Psc.Insights.Detector do
  @moduledoc """
  A content detector.

  `run/1` receives a `Psc.Insights.Context` and returns a list of raw finding
  maps. It must be pure and deterministic: the same context always produces
  the same findings. The report normalises and orders the output.
  """

  @callback key() :: String.t()
  @callback run(Psc.Insights.Context.t()) :: [map()]
end
