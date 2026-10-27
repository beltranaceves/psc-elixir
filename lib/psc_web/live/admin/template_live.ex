defmodule PscWeb.Admin.TemplateLive do
  @moduledoc """
  Administration of templates, including the built-in defaults.

  Editing goes through `Psc.Canvas.Layout.changeset/2`, so the structure is
  still validated. `built_in` and the counts are read-only: the seed owns the
  flag, and the counters are moved by `Psc.Canvas` with atomic increments.

  Built-in templates cannot be deleted — other users start from them — but
  they can be renamed or unpublished from the edit form.
  """

  use Backpex.LiveResource,
    adapter_config: [
      schema: Psc.Canvas.Layout,
      repo: Psc.Repo,
      update_changeset: &__MODULE__.changeset/3,
      create_changeset: &__MODULE__.changeset/3
    ],
    init_order: %{by: :updated_at, direction: :desc},
    fluid?: true

  alias Psc.Accounts
  alias Psc.Canvas.Layout

  import Ecto.Query

  @impl Backpex.LiveResource
  def singular_name, do: "Template"

  @impl Backpex.LiveResource
  def plural_name, do: "Templates"

  @impl Backpex.LiveResource
  def layout(_assigns), do: {PscWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def filters do
    [
      public: %{module: PscWeb.Admin.Filters.TemplateVisibility},
      built_in: %{module: PscWeb.Admin.Filters.TemplateOrigin}
    ]
  end

  @impl Backpex.LiveResource
  def metrics do
    [
      templates: %{
        module: Backpex.Metrics.Value,
        label: "Templates",
        select: dynamic([template], count(template.id)),
        format: &Integer.to_string/1
      },
      instantiations: %{
        module: Backpex.Metrics.Value,
        label: "Instantiations",
        select: dynamic([template], sum(template.use_count)),
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
        orderable: true
      },
      description: %{
        module: Backpex.Fields.Textarea,
        label: "Description",
        except: [:index]
      },
      public: %{
        module: Backpex.Fields.Boolean,
        label: "Public (catalog)"
      },
      built_in: %{
        module: Backpex.Fields.Boolean,
        label: "Built-in",
        readonly: true,
        except: [:new, :edit]
      },
      author: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        display_field: :email,
        readonly: true,
        except: [:new, :edit]
      },
      use_count: %{
        module: Backpex.Fields.Number,
        label: "Uses",
        readonly: true,
        except: [:new, :edit]
      },
      fork_count: %{
        module: Backpex.Fields.Number,
        label: "Forks",
        readonly: true,
        except: [:new, :edit]
      },
      updated_at: %{
        module: Backpex.Fields.DateTime,
        label: "Updated",
        readonly: true,
        except: [:new, :edit]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(_assigns, :delete, %Layout{built_in: true}), do: false

  def can?(assigns, action, _item) when action in [:index, :show, :edit, :delete],
    do: admin?(assigns)

  def can?(_assigns, _action, _item), do: false

  @doc """
  The template changeset. It cannot make a row built-in: those fields are
  deliberately outside `Layout.changeset/2`.
  """
  def changeset(template_or_changeset, attrs, _metadata) do
    Layout.changeset(template_or_changeset, attrs)
  end

  defp admin?(assigns), do: Accounts.admin?(assigns.current_scope.user)
end
