defmodule Psc.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field :title, :string
    field :content, :string
    field :crdt_state, :string
    field :shared_with, {:array, :string}, default: []
    field :snapshot_content, :string, default: ""
    field :snapshot_seq, :integer, default: 0

    belongs_to :user, Psc.Accounts.User
    has_many :events, Psc.Documents.DocumentEvent, foreign_key: :document_id

    timestamps()
  end

  @doc false
  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :title,
      :content,
      :crdt_state,
      :user_id,
      :shared_with,
      :snapshot_content,
      :snapshot_seq
    ])
    |> validate_required([:title, :user_id])
  end
end
