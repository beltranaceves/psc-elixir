defmodule Psc.Agent.Jido do
  @moduledoc """
  The Jido instance this application runs its agents under.

  Starting an `AgentServer` needs somewhere for Jido to put its registry,
  supervisor and runtime store. Naming the instance after us keeps those
  processes out of the default `Jido.*` namespace, which another library could
  claim, and makes them visible in the supervision tree.
  """

  use Jido, otp_app: :psc
end
