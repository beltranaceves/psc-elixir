defmodule PscWeb.Admin.CanvasLive do
  @moduledoc """
  Read-only administration of canvases.

  A canvas's content is event-sourced and belongs to the collaborative editor;
  editing it from an admin table would bypass the event log and the CRDT, so
  this resource is index/show only.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Psc.Canvas.UnstrCanvas,
      repo: Psc.Repo,
      update_changeset: &__MODULE__.changeset/3,
      create_changeset: &__MODULE__.changeset/3
    ],
    init_order: %{by: :updated_at, direction: :desc},
    fluid?: true

  alias Psc.Accounts

  import Ecto.Query

  @impl Backpex.LiveResource
  def singular_name, do: "Canvas"

  @impl Backpex.LiveResource
  def plural_name, do: "Canvases"

  @impl Backpex.LiveResource
  def layout(_assigns), do: {PscWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def filters do
    [notes_mode: %{module: PscWeb.Admin.Filters.CanvasNotesMode}]
  end

  @impl Backpex.LiveResource
  def metrics do
    [
      canvases: %{
        module: Backpex.Metrics.Value,
        label: "Canvases",
        select: dynamic([canvas], count(canvas.id)),
        format: &Integer.to_string/1
      }
    ]
  end

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true,
        orderable: true,
        readonly: true
      },
      author: %{
        module: Backpex.Fields.BelongsTo,
        label: "Owner",
        display_field: :email,
        readonly: true,
        except: [:new, :edit]
      },
      description: %{
        module: Backpex.Fields.Textarea,
        label: "Description",
        readonly: true,
        except: [:index]
      },
      notes_mode: %{
        module: Backpex.Fields.Select,
        label: "Notes mode",
        options: [Multi: "multi", Single: "single"],
        readonly: true,
        except: [:index]
      },
      snapshot_seq: %{
        module: Backpex.Fields.Number,
        label: "Snapshot",
        readonly: true,
        except: [:index]
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        readonly: true
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
  def changeset(canvas_or_changeset, _attrs, _metadata) do
    Ecto.Changeset.change(canvas_or_changeset)
  end

  defp admin?(assigns), do: Accounts.admin?(assigns.current_scope.user)
end
