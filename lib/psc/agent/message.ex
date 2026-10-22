defmodule Psc.Agent.Message do
  @moduledoc """
  One message in a session: the user's prompt, or the agent's answer with the
  tool calls that produced it.

  `tool_calls` is a list of `%{"name", "arguments", "result", "status",
  "duration_ms"}` maps. It is stored for display and for replay, and the replay
  uses a rendering of this list rather than the JSONB itself - Postgres does not
  preserve key order, and the cacheable prefix has to be byte-stable.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @roles [:user, :assistant]
  @statuses [:streaming, :complete, :cancelled, :error]

  schema "agent_messages" do
    field :role, Ecto.Enum, values: @roles
    field :content, :string, default: ""
    field :status, Ecto.Enum, values: @statuses, default: :complete
    field :error, :string
    field :tool_calls, {:array, :map}, default: []
    field :usage, :map

    belongs_to :session, Psc.Agent.Session, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def roles, do: @roles
  def statuses, do: @statuses

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :status, :error, :tool_calls, :usage, :session_id])
    |> validate_required([:role, :session_id])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
  end
end
