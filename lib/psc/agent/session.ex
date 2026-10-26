defmodule Psc.Agent.Session do
  @moduledoc """
  One chat thread with the agent.

  Sessions are rows, agents are not: everything a turn needs is rebuilt from
  these rows and `Psc.Agent.Message`, so a deploy in the middle of a
  conversation costs nothing but the turn in flight.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "agent_sessions" do
    field :title, :string, default: "New chat"
    field :message_count, :integer, default: 0
    field :last_message_at, :utc_datetime_usec

    # Pinned when the first message is sent. A chat keeps the agent set-up it
    # started with, so editing the canvas cannot change an answer in flight and
    # the provider's cacheable prefix stays byte-stable.
    field :role, :string
    field :profile, :map

    belongs_to :user, Psc.Accounts.User
    belongs_to :canvas, Psc.Canvas.UnstrCanvas, type: :binary_id
    belongs_to :connection, Psc.Agent.Connection, type: :binary_id
    has_many :messages, Psc.Agent.Message, foreign_key: :session_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Renames a session. Titles are display-only; the turn prompt never reads them.
  """
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:title])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 120)
  end
end
