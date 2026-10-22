defmodule Psc.Agent.Tools.Scope do
  @moduledoc """
  Pulls the caller out of the tool context.

  The turn passes `tool_context: %{scope: current_scope}`, so every tool runs as
  the person who asked. A missing scope is an error, never a fallback to some
  other user.
  """

  alias Psc.Accounts.Scope, as: AccountsScope
  alias Psc.Accounts.User

  @doc "The signed-in user behind this tool call."
  def user(context) do
    case Map.get(context, :scope) || Map.get(context, "scope") do
      %AccountsScope{user: %User{} = user} -> {:ok, user}
      _other -> {:error, "No signed-in user is attached to this request."}
    end
  end

  @doc "Casts a UUID argument, with a message the model can act on."
  def uuid(value, label) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, "#{label} must be a UUID."}
    end
  end

  @doc "Formats an Ecto timestamp for the model."
  def iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def iso8601(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def iso8601(nil), do: nil
end
