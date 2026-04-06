defmodule Psc.Documents.DocumentEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "document_events" do
    field :operation, :map
    field :seq, :integer

    belongs_to :document, Psc.Documents.Document
    belongs_to :user, Psc.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:operation, :seq, :document_id, :user_id])
    |> validate_required([:operation, :seq, :document_id, :user_id])
  end
end
