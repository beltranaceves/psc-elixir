defmodule Psc.Agent.TurnConfig do
  @moduledoc """
  What one turn will call: the model spec, the provider credential and the
  endpoint, resolved once before the turn starts.

  Resolution happens before the task is spawned (see
  `Psc.Agent.Connections.turn_config/2`), so editing or deleting a connection
  while an answer streams cannot change the request in flight. `api_key` is
  redacted in inspections and never rendered.
  """

  @type t :: %__MODULE__{
          connection_id: binary() | nil,
          model: String.t() | nil,
          api_key: String.t() | nil,
          base_url: String.t() | nil
        }

  defstruct [:connection_id, :model, :api_key, :base_url]
end
