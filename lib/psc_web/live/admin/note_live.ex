defmodule PscWeb.Admin.NoteLive do
  @moduledoc """
  Read-only administration of notes.

  A note's body lives in its event log and is folded by `Psc.TextStore`; it is
  edited in the canvas's Notes view, never from a plain admin form. The titles
  and the canvas they belong to are visible here for moderation.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Psc.Notes.Note,
      repo: Psc.Repo,
      update_changeset: &__MODULE__.changeset/3,
      create_changeset: &__MODULE__.changeset/3
    ],
    init_order: %{by: :updated_at, direction: :desc},
    fluid?: true

  alias Psc.Accounts

  import Ecto.Query

  @impl Backpex.LiveResource
  def singular_name, do: "Note"

  @impl Backpex.LiveResource
  def plural_name, do: "Notes"

  @impl Backpex.LiveResource
  def layout(_assigns), do: {PscWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def metrics do
    [
      notes: %{
        module: Backpex.Metrics.Value,
        label: "Notes",
        select: dynamic([note], count(note.id)),
        format: &Integer.to_string/1
      }
    ]
  end

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{
        module: Backpex.Fields.Text,
        label: "Title",
        searchable: true,
        orderable: true,
        readonly: true
      },
      canvas: %{
        module: Backpex.Fields.BelongsTo,
        label: "Canvas",
        display_field: :name,
        readonly: true
      },
      created_by: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        display_field: :email,
        readonly: true
      },
      snapshot_seq: %{
        module: Backpex.Fields.Number,
        label: "Snapshot",
        readonly: true,
        except: [:index]
      },
      updated_at: %{
        module: Backpex.Fields.DateTime,
        label: "Updated",
        readonly: true
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, action, _item) when action in [:index, :show], do: admin?(assigns)
  def can?(_assigns, _action, _item), do: false

  @doc """
  A no-op changeset: this resource never writes.
  """
  def changeset(note_or_changeset, _attrs, _metadata) do
    Ecto.Changeset.change(note_or_changeset)
  end

  defp admin?(assigns), do: Accounts.admin?(assigns.current_scope.user)
end
