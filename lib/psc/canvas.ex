defmodule Psc.Canvas do
  @moduledoc """
  The Canvas context for managing strategic planning canvases.
  Supports collaborative editing with cell-level operations.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Psc.Repo
  alias Psc.Canvas.UnstrCanvas
  alias Psc.Canvas.Layout
  alias Psc.Canvas.NotesMode
  alias Psc.Canvas.Structure
  alias Psc.Agent.Config, as: AgentConfig
  alias Psc.Agent.Files, as: AgentFiles

  # The built-in Problem–Solution Canvas: the 12-cell grid (Perceive / Form /
  # Consolidate / Learn × Rationale / Strategy / Tactics) that used to be the
  # schema's silent default. It is an explicit choice now — the picker's PSC
  # card — so a canvas without a template can be truly blank.
  @psc_cells %{
    "columns" => [
      %{"id" => "perceive", "label" => "Perceive"},
      %{"id" => "form", "label" => "Form"},
      %{"id" => "consolidate", "label" => "Consolidate"},
      %{"id" => "learn", "label" => "Learn"}
    ],
    "rows" => [
      %{"id" => "rationale", "label" => "Rationale"},
      %{"id" => "strategy", "label" => "Strategy"},
      %{"id" => "tactics", "label" => "Tactics"}
    ],
    "layout" => [
      ["problem", "leverage", "solution_cluster", "horizon"],
      ["outer_environment", "inner_environment", "evolvability_cluster", "potential"],
      ["manifestations", "capabilities", "merit_cluster", "mission"]
    ],
    "problem" => %{
      "row" => "rationale",
      "column" => "perceive",
      "content" => ""
    },
    "leverage" => %{
      "row" => "rationale",
      "column" => "form",
      "technology" => "",
      "components" => "",
      "information" => "",
      "human_resources" => ""
    },
    "solution_cluster" => %{
      "row" => "rationale",
      "column" => "consolidate",
      "content" => ""
    },
    "horizon" => %{
      "row" => "rationale",
      "column" => "learn",
      "content" => ""
    },
    "outer_environment" => %{
      "row" => "strategy",
      "column" => "perceive",
      "external_services" => "",
      "external_implements" => "",
      "external_repositories" => "",
      "external_people" => ""
    },
    "inner_environment" => %{
      "row" => "strategy",
      "column" => "form",
      "content" => ""
    },
    "evolvability_cluster" => %{
      "row" => "strategy",
      "column" => "consolidate",
      "evolvability" => "",
      "diffusibility" => "",
      "adoptability" => ""
    },
    "potential" => %{
      "row" => "strategy",
      "column" => "learn",
      "content" => ""
    },
    "manifestations" => %{
      "row" => "tactics",
      "column" => "perceive",
      "content" => ""
    },
    "capabilities" => %{
      "row" => "tactics",
      "column" => "form",
      "content" => ""
    },
    "merit_cluster" => %{
      "row" => "tactics",
      "column" => "consolidate",
      "merit" => "",
      "value" => "",
      "reservation" => "",
      "rebuttal" => ""
    },
    "mission" => %{
      "row" => "tactics",
      "column" => "learn",
      "content" => ""
    }
  }

  @doc """
  The built-in Problem–Solution Canvas structure, for the picker's PSC card.
  """
  def psc_cells, do: @psc_cells

  @doc """
  The empty structure: a canvas with no rows and no columns yet, built in
  place with structure editing.
  """
  def blank_cells, do: %UnstrCanvas{}.cells

  @doc """
  Returns the display title for a cell field.

  A template cell may carry a `"titles"` map keyed by field name; an entry
  whose value is empty means the section is intentionally untitled. Without an
  entry the field key is the title, except for the conventional `"content"`
  body field, which is untitled so it can use the whole cell height.
  """
  def field_title(cell_data, field) do
    case Map.fetch(cell_data["titles"] || %{}, field) do
      {:ok, title} -> title |> to_string() |> String.trim()
      :error -> if field == "content", do: "", else: field
    end
  end

  ## Unstructured Canvas Functions

  @doc """
  List saved canvas layouts.
  """
  def list_canvas_layouts do
    Layout
    |> order_by([l], desc: l.inserted_at)
    |> Repo.all()
  end

  @doc """
  Get a single canvas layout by id.
  """
  def get_canvas_layout(id) do
    Repo.get(Layout, id)
  end

  @doc """
  Create a canvas layout.
  """
  def create_canvas_layout(attrs \\ %{}) do
    %Layout{}
    |> Layout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a canvas layout.
  """
  def update_canvas_layout(layout, attrs) do
    layout
    |> Layout.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a canvas layout.
  """
  def delete_canvas_layout(layout) do
    Repo.delete(layout)
  end

  # ─── Template functions ───

  @doc """
  List all templates a user can access: their own, those shared with them, and
  the built-in templates every user may start from.
  """
  def list_templates(user) do
    from(l in Layout,
      where:
        l.built_in == true or l.author_id == ^user.id or
          fragment("? = ANY(?)", ^user.email, l.shared_with),
      order_by: [desc: l.built_in, desc: l.updated_at]
    )
    |> preload(:author)
    |> Repo.all()
  end

  @doc """
  Get a built-in template by its stable slug.
  """
  def get_template_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Layout, slug: slug, built_in: true)
  end

  @doc """
  Get a template with author preloaded.
  """
  def get_template_with_author(id) do
    Layout
    |> preload(:author)
    |> Repo.get(id)
  end

  @doc """
  Create a template authored by the given user.
  """
  def create_template(user_id, attrs \\ %{}) do
    %Layout{author_id: user_id}
    |> Layout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a template.
  """
  def update_template(template, attrs) do
    template
    |> Layout.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a template.

  Built-in templates are refused: other users start from them, and the seed
  would recreate a missing one on the next boot anyway.
  """
  def delete_template(%Layout{built_in: true}), do: {:error, :built_in}
  def delete_template(template), do: Repo.delete(template)

  # ─── Built-in templates ───

  # Seeded on boot and on every `mix ecto.setup`. They belong to nobody and are
  # readable by everyone; the admin surface can publish or rename them, and the
  # seed only creates the ones that are missing, so an edit survives a restart.
  @builtin_templates [
    %{
      slug: "psc",
      name: "Problem–Solution Canvas",
      description:
        "The classic 12-cell framework: Perceive, Form, Consolidate and Learn " <>
          "across Rationale, Strategy and Tactics."
    },
    %{
      slug: "scratchpad",
      name: "Scratchpad",
      description: "One page and a single note, for free-form thinking."
    },
    %{
      slug: "bento",
      name: "Bento Board",
      description:
        "Free-form cards on a 12-column board: a big picture, supporting " <>
          "evidence, a decision and the open questions."
    },
    %{
      slug: "image",
      name: "Image Board",
      description:
        "Float notes and labels over a backdrop picture: pin the brief, the " <>
          "risks and the next step to the places they belong."
    }
  ]

  @doc """
  The built-in templates the instance ships with.
  """
  def builtin_templates, do: Enum.map(@builtin_templates, & &1.slug)

  @doc """
  Create any missing built-in template. Idempotent by slug.

  Existing rows are left untouched: an administrator may have renamed or
  unpublished one, and a reboot must not undo that. Returns
  `{created, already_present}`.
  """
  def seed_builtin_templates do
    Enum.reduce(@builtin_templates, {0, 0}, fn definition, {created, present} ->
      case Repo.get_by(Layout, slug: definition.slug) do
        nil ->
          attrs = %{
            name: definition.name,
            description: definition.description,
            layout_map: builtin_layout_map(definition.slug),
            public: true
          }

          %Layout{}
          |> Layout.changeset(attrs)
          # Both fields are system-set and stay out of `Layout.changeset/2`.
          |> Ecto.Changeset.change(built_in: true, slug: definition.slug)
          |> Repo.insert()
          |> case do
            {:ok, _template} ->
              {created + 1, present}

            {:error, changeset} ->
              Logger.warning(
                "could not seed the built-in template #{definition.slug}: #{inspect(changeset.errors)}"
              )

              {created, present}
          end

        _existing ->
          {created, present + 1}
      end
    end)
  end

  defp builtin_layout_map("psc"), do: psc_layout_map()
  defp builtin_layout_map("scratchpad"), do: scratchpad_layout_map()
  defp builtin_layout_map("bento"), do: bento_layout_map()
  defp builtin_layout_map("image"), do: image_layout_map()

  @doc """
  The Problem–Solution Canvas as a template definition.

  Derived from `psc_cells/0`, so the built-in template and the picker's
  structure cannot drift apart.
  """
  def psc_layout_map do
    cells =
      @psc_cells
      |> Map.drop(["rows", "columns", "layout"])
      |> Map.new(fn {key, data} ->
        fields =
          data
          |> Map.keys()
          |> Enum.reject(&(&1 in ["row", "column"]))
          |> Enum.sort()

        {key,
         %{
           "label" => humanize_key(key),
           "fields" => fields,
           "defaults" => Map.new(fields, fn field -> {field, ""} end)
         }}
      end)

    %{
      "rows" => @psc_cells["rows"],
      "columns" => @psc_cells["columns"],
      "layout" => @psc_cells["layout"],
      "cells" => cells,
      "notes_mode" => "multi"
    }
  end

  @doc """
  A one-page template that opens its canvas in single-note mode.
  """
  def scratchpad_layout_map do
    %{
      "rows" => [%{"id" => "r1", "label" => "Scratchpad"}],
      "columns" => [%{"id" => "c1", "label" => "Notes"}],
      "layout" => [["r1_c1"]],
      "cells" => %{
        "r1_c1" => %{
          "label" => "Scratchpad",
          "fields" => ["content"],
          "defaults" => %{"content" => ""}
        }
      },
      "notes_mode" => "single"
    }
  end

  @doc """
  The built-in bento template: four cards on a 12-column board.

  A bento template is stored in the same flat shape as a bento canvas - one
  entry per card, with a `"placement"` - so validation, instantiation and the
  editor share one representation.
  """
  def bento_layout_map do
    card = fn label, fields, x, y, w, h, accent ->
      %{
        "label" => label,
        "fields" => fields,
        "defaults" => Map.new(fields, &{&1, ""}),
        "placement" => %{"x" => x, "y" => y, "w" => w, "h" => h},
        "accent" => accent
      }
    end

    %{
      "layout_mode" => "bento",
      "bento_columns" => 12,
      "bento_rows" => 5,
      "big_picture" => card.("Big picture", ["content"], 0, 0, 8, 3, "sky"),
      "evidence" => card.("Evidence", ["content"], 8, 0, 4, 3, "emerald"),
      "decision" => card.("Decision", ["content"], 0, 3, 6, 2, "violet"),
      "open_questions" => card.("Open questions", ["content"], 6, 3, 6, 2, "amber"),
      "notes_mode" => "multi"
    }
  end

  @doc """
  The backdrop a new image board starts with.

  A light blueprint grid with three marked zones, so a template can be
  designed (and a canvas used) before the user brings their own picture. It is
  a static asset, which keeps the template row small and the URL readable in
  the stored `layout_map`.
  """
  def image_backdrop_url, do: "/images/image-board-blueprint.svg"

  @doc """
  The built-in image board: a backdrop picture with floating cards and a text
  label.

  An image template is flat like a bento one - one entry per cell, with a
  `placement` in percent of the backdrop - so validation, instantiation and
  both editors share one representation.
  """
  def image_layout_map do
    cell = fn label, fields, defaults, placement, kind, accent ->
      %{
        "label" => label,
        "fields" => fields,
        "defaults" => Map.new(fields, &{&1, Map.get(defaults, &1, "")}),
        "placement" => placement,
        "kind" => kind
      }
      |> Map.put("accent", accent)
    end

    %{
      "layout_mode" => "image",
      "backdrop" => %{
        "url" => image_backdrop_url(),
        "fit" => "contain",
        "alt" => "Blueprint grid with three marked zones"
      },
      "brief" =>
        cell.(
          "Brief",
          ["content"],
          %{"content" => ""},
          %{"x" => 4, "y" => 8, "w" => 28, "h" => 18},
          "card",
          "sky"
        ),
      "risk" =>
        cell.(
          "Risk",
          ["content"],
          %{"content" => ""},
          %{"x" => 68, "y" => 8, "w" => 28, "h" => 16},
          "card",
          "amber"
        ),
      "next_step" =>
        cell.(
          "Next step",
          ["content"],
          %{"content" => "Next step"},
          %{"x" => 34, "y" => 78, "w" => 32, "h" => 8},
          "text",
          nil
        ),
      "notes_mode" => "multi"
    }
  end

  defp humanize_key(key) do
    key
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Share a template with a user by email (idempotent).
  """
  def share_template_with(template, email) do
    shared_with = template.shared_with || []
    new_shared_with = Enum.uniq([email | shared_with])
    update_template(template, %{"shared_with" => new_shared_with})
  end

  @doc """
  Remove a user's access to a template.
  """
  def unshare_template(template, email) do
    shared_with = template.shared_with || []
    new_shared_with = List.delete(shared_with, email)
    update_template(template, %{"shared_with" => new_shared_with})
  end

  @doc """
  Check if a user can access a template (author or shared).
  """
  def can_access_template?(template, user_email) do
    author = template.author

    cond do
      template.built_in -> true
      author && author.email == user_email -> true
      user_email in (template.shared_with || []) -> true
      true -> false
    end
  end

  ## Catalog functions

  @catalog_limit 200

  @doc """
  List the public templates, ranked by how many times they have been used.

  `query` narrows the ranking with a case-insensitive match on the name and the
  description. The result is capped: the catalog is a ranking, not an index, and
  the free tier caps the table at 10 000 rows (ADR-006).
  """
  def list_public_templates(query \\ nil) do
    Layout
    |> where([l], l.public == true)
    |> maybe_search(query)
    |> order_by([l], desc: l.use_count, desc: l.updated_at)
    |> limit(^@catalog_limit)
    |> preload(:author)
    |> Repo.all()
  end

  defp maybe_search(queryable, nil), do: queryable

  defp maybe_search(queryable, query) when is_binary(query) do
    pattern = "%#{escape_like(query)}%"

    where(queryable, [l], ilike(l.name, ^pattern) or ilike(l.description, ^pattern))
  end

  # ILIKE treats % and _ as wildcards, so a user searching for one should find
  # the templates that contain it rather than every template.
  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc """
  The most templates the catalog ranks.

  The catalog is a ranking, not an index, so a page never renders the whole
  table — the free tier caps it at 10 000 rows (ADR-006).
  """
  def catalog_limit, do: @catalog_limit

  @doc """
  Get a public template with its author, or nil.

  The fetch behind the catalog's modal and both of its actions: a template that
  is not public is not found here, so the catalog cannot be used to reach a
  private one.
  """
  def get_public_template(id) do
    Layout
    |> where([l], l.public == true)
    |> preload(:author)
    |> Repo.get(id)
  end

  @doc """
  Mark a template public, so it is listed in the catalog.
  """
  def publish_template(template), do: update_template(template, %{"public" => true})

  @doc """
  Mark a template private again.

  Canvases and forks already made are copies and keep working; the template
  just leaves the catalog.
  """
  def unpublish_template(template), do: update_template(template, %{"public" => false})

  @doc """
  Fork a template: a copy the caller owns, independent of its source (ADR-009).

  The copy carries the source's name, description and definition, and records
  the lineage. The source's fork count goes up by one in the same transaction,
  so a fork is never made without being counted.
  """
  # Template names are unique, so forking the same source twice needs two
  # names: the first fork is "Name (fork)", the ones after it number
  # themselves.
  @fork_attempts 5

  def fork_template(template, user_id) do
    Enum.reduce_while(1..@fork_attempts, {:error, :name_taken}, fn attempt, acc ->
      case fork_once(template, user_id, attempt) do
        {:ok, fork} ->
          {:halt, {:ok, fork}}

        {:error, %Ecto.Changeset{} = changeset} ->
          if name_taken?(changeset), do: {:cont, acc}, else: {:halt, {:error, changeset}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Template names are unique, so forking the same source twice needs two
  # names: the first fork is "Name (fork)", the ones after it number
  # themselves. Each attempt is its own transaction, because a name that is
  # already taken aborts the transaction it was tried in — retrying inside one
  # transaction would only meet "transaction is aborted" for the rest of it.
  defp fork_once(template, user_id, attempt) do
    Repo.transaction(fn ->
      with {:ok, fork} <- create_template(user_id, fork_attrs(template, attempt)),
           {:ok, fork} <- record_lineage(fork, template.id),
           {:ok, _template} <- bump_count(template, :fork_count) do
        AgentFiles.copy_to_template(template.id, fork.id)
        fork
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp fork_attrs(template, attempt) do
    %{
      "name" => fork_name(template.name, attempt),
      "description" => template.description || "",
      "layout_map" => template.layout_map || %{},
      "agent_config" => template.agent_config || %{}
    }
  end

  defp fork_name(name, 1), do: "#{name} (fork)"
  defp fork_name(name, attempt), do: "#{name} (fork #{attempt})"

  defp record_lineage(fork, source_id) do
    fork
    |> Ecto.Changeset.change(forked_from_id: source_id)
    |> Repo.update()
  end

  defp name_taken?(%Ecto.Changeset{} = changeset) do
    case Keyword.fetch(changeset.errors, :name) do
      {:ok, {_message, constraints}} when is_list(constraints) ->
        Keyword.get(constraints, :constraint) == :unique

      _ ->
        false
    end
  end

  # A counter moves with a single `inc`, never a read-modify-write: two
  # simultaneous uses would otherwise lose one.
  defp bump_count(template, counter) do
    query = from(l in Layout, where: l.id == ^template.id)
    {count, _} = Repo.update_all(query, inc: [{counter, 1}])

    if count == 1, do: {:ok, template}, else: {:error, :not_found}
  end

  @doc """
  Instantiate a canvas from a template.

  Transforms the template's layout_map (cells nested under "cells" with
  label/fields/defaults metadata) into the canvas cells shape
  (flat cell keys with row/column metadata and field values), per the
  editor spec.

  The template's notes are copied too: a note is part of the template's
  definition, so a canvas made from it starts with the same notes. The copy
  is independent — editing a note in the canvas never touches the template
  (ADR-009).

  `overrides` lets the caller supply a user-chosen name/description; anything
  not given falls back to the template's own values.

  The canvas, its notes and the template's `use_count` are written in one
  transaction: a canvas is never created without its use being counted, and a
  count is never bumped without a canvas. Every instantiation counts, from the
  library as well as the catalog.
  """
  def instantiate_template(template, user_id, overrides \\ %{}) do
    lm = template.layout_map || %{}

    cells =
      case Structure.mode(lm) do
        :bento ->
          instantiate_bento_cells(lm)

        :image ->
          instantiate_image_cells(lm)

        :table ->
          rows = lm["rows"] || []
          columns = lm["columns"] || []
          layout = lm["layout"] || []
          template_cells = lm["cells"] || %{}

          %{"rows" => rows, "columns" => columns, "layout" => layout}
          |> put_instantiated_cells(template_cells, layout, rows, columns)
      end

    attrs =
      %{
        "name" => template.name,
        "description" => template.description || "",
        "cells" => cells,
        # The note mode is a property of the template, not of the canvas.
        "notes_mode" => NotesMode.normalize(lm["notes_mode"]),
        # The agent's setup is a copy, like the cells and the notes.
        "agent_config" => AgentConfig.normalize(template.agent_config)
      }
      |> Map.merge(Map.reject(overrides || %{}, fn {_k, v} -> is_nil(v) or v == "" end))

    Repo.transaction(fn ->
      with {:ok, canvas} <- create_unstr_canvas(user_id, attrs),
           {:ok, canvas} <- record_agent_source(canvas, template),
           {:ok, _template} <- bump_count(template, :use_count) do
        Psc.Notes.seed_notes(canvas, lm["notes"] || [])
        AgentFiles.copy_to_canvas(template.id, canvas.id)
        canvas
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp record_agent_source(canvas, template) do
    canvas
    |> Ecto.Changeset.change(
      source_template_id: template.id,
      agent_config_source_hash: AgentConfig.hash(template.agent_config)
    )
    |> Repo.update()
  end

  defp put_instantiated_cells(cells, template_cells, layout, rows, columns) do
    layout
    |> Enum.with_index()
    |> Enum.reduce(cells, fn {row_keys, ri}, acc ->
      row_keys
      |> Enum.with_index()
      |> Enum.reduce(acc, fn
        {nil, _ci}, a ->
          a

        {key, ci}, a ->
          meta = template_cells[key] || %{}
          row_id = Enum.at(rows, ri, %{"id" => "r#{ri}"})["id"]
          column_id = Enum.at(columns, ci, %{"id" => "c#{ci}"})["id"]
          fields = template_fields(meta)

          data =
            fields
            |> Map.new(fn field -> {field, Map.get(meta["defaults"] || %{}, field, "")} end)
            |> Map.merge(%{
              "row" => row_id,
              "column" => column_id,
              "label" => meta["label"] || key,
              "field_order" => fields
            })
            |> maybe_put_titles(meta["titles"])

          Map.put(a, key, data)
      end)
    end)
  end

  defp maybe_put_titles(data, titles) when titles in [nil, %{}], do: data
  defp maybe_put_titles(data, titles), do: Map.put(data, "titles", titles)

  # A template's field list becomes the canvas cell's value keys and its
  # render order. Reserved names are definition metadata, never values; a
  # template saved before they were rejected must not turn one into a field.
  defp template_fields(meta) do
    case Enum.reject(meta["fields"] || ["content"], &(&1 in Structure.reserved_cell_keys())) do
      [] -> ["content"]
      fields -> fields
    end
  end

  # A bento template already has the canvas shape: flat cards with a
  # placement. Only the fields change from a definition to a value.
  defp instantiate_bento_cells(lm) do
    cards =
      lm
      |> Structure.cells()
      |> Map.new(fn {key, meta} ->
        fields = template_fields(meta)

        data =
          fields
          |> Map.new(fn field -> {field, Map.get(meta["defaults"] || %{}, field, "")} end)
          |> Map.merge(%{
            "label" => meta["label"] || key,
            "placement" => meta["placement"],
            "field_order" => fields
          })
          |> maybe_put_titles(meta["titles"])
          |> maybe_put_accent(meta["accent"])

        {key, data}
      end)

    cards
    |> Map.put("layout_mode", "bento")
    |> Map.put("bento_columns", Structure.columns(lm))
    |> Map.put("bento_rows", Structure.rows(lm))
  end

  defp maybe_put_accent(data, accent) when accent in [nil, ""], do: data
  defp maybe_put_accent(data, accent), do: Map.put(data, "accent", accent)

  # An image template is flat like a bento one. The canvas copies the
  # backdrop and every cell's percentage placement, kind and accent, and turns
  # each field's default into the cell's starting value.
  defp instantiate_image_cells(lm) do
    cells =
      lm
      |> Structure.cells()
      |> Enum.filter(fn {_key, meta} -> is_map(meta) end)
      |> Map.new(fn {key, meta} ->
        fields = template_fields(meta)

        data =
          fields
          |> Map.new(fn field -> {field, Map.get(meta["defaults"] || %{}, field, "")} end)
          |> Map.merge(%{
            "label" => meta["label"] || key,
            "placement" => meta["placement"],
            "kind" => Structure.kind(meta),
            "field_order" => fields
          })
          |> maybe_put_titles(meta["titles"])
          |> maybe_put_accent(meta["accent"])

        {key, data}
      end)

    cells
    |> Map.put("layout_mode", "image")
    |> maybe_put_backdrop(Structure.backdrop_map(lm))
  end

  defp maybe_put_backdrop(cells, backdrop) when backdrop == %{}, do: cells
  defp maybe_put_backdrop(cells, backdrop), do: Map.put(cells, "backdrop", backdrop)

  @doc """
  List all unstructured canvases authored by a user.
  """
  def list_user_unstr_canvases(user_id) do
    from(c in UnstrCanvas, where: c.author_id == ^user_id, order_by: [desc: c.updated_at])
    |> preload(:author)
    |> Repo.all()
  end

  @doc """
  List all unstructured canvases shared with a user by email.
  """
  def list_shared_unstr_canvases(user_email) do
    from(c in UnstrCanvas,
      where: fragment("? = ANY(?)", ^user_email, c.shared_with),
      order_by: [desc: c.updated_at]
    )
    |> preload(:author)
    |> Repo.all()
  end

  @doc """
  Get a single unstructured canvas by id.
  """
  def get_unstr_canvas(id) do
    Repo.get(UnstrCanvas, id)
  end

  @doc """
  Get an unstructured canvas with author preloaded.
  """
  def get_unstr_canvas_with_author(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        UnstrCanvas
        |> preload(:author)
        |> Repo.get(uuid)

      :error ->
        nil
    end
  end

  @doc """
  Create a new unstructured canvas.

  The `cells` come from the caller: the picker's blank card passes
  `blank_cells/0`, its PSC card passes `psc_cells/0`, and instantiating a
  template builds them from the template. With no `cells` in the attrs the
  schema's empty-structure default applies.
  """
  def create_unstr_canvas(user_id, attrs \\ %{}) do
    # Ensure params use string keys (avoid mixing atom and string keys)
    all_attrs =
      attrs
      |> Map.put("author_id", user_id)

    %UnstrCanvas{}
    |> UnstrCanvas.changeset(all_attrs)
    |> Repo.insert()
  end

  @doc """
  Update an unstructured canvas.
  """
  def update_unstr_canvas(canvas, attrs) do
    canvas
    |> UnstrCanvas.changeset(attrs)
    |> Repo.update(stale_error_field: :base)
  end

  ## Canvas agent setup

  @doc """
  Saves a canvas's agent config and its reference files together.

  The config is normalized by the schema; the files are replaced as a set. A
  broadcast lets other open tabs refresh their copy without a reload.
  """
  def update_agent_config(%UnstrCanvas{} = canvas, config, drafts) do
    changeset =
      canvas
      |> UnstrCanvas.changeset(%{"agent_config" => config})

    Repo.transaction(fn ->
      with {:ok, canvas} <- Repo.update(changeset, stale_error_field: :base),
           {:ok, :ok} <- AgentFiles.replace(:canvas, canvas.id, drafts) do
        broadcast_agent_config(canvas.id)
        canvas
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Replaces a canvas's agent config and files with the current template's.

  Only available while the source template exists. The canvas keeps its own
  copy either way; this is an explicit one-way refresh, not a link.
  """
  def reset_agent_config(%UnstrCanvas{} = canvas) do
    with template_id when is_binary(template_id) <- canvas.source_template_id,
         %Layout{} = template <- get_canvas_layout(template_id) do
      config = AgentConfig.normalize(template.agent_config)
      drafts = AgentFiles.drafts(:template, template.id)

      Repo.transaction(fn ->
        with {:ok, canvas} <-
               canvas
               |> Ecto.Changeset.change(
                 agent_config: config,
                 agent_config_source_hash: AgentConfig.hash(config)
               )
               |> Repo.update(),
             {:ok, :ok} <- AgentFiles.replace(:canvas, canvas.id, drafts) do
          broadcast_agent_config(canvas.id)
          canvas
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      _other -> {:error, :no_template}
    end
  end

  @doc "The template this canvas was made from, if it still exists."
  def agent_source_template(%UnstrCanvas{source_template_id: nil}), do: nil

  def agent_source_template(%UnstrCanvas{source_template_id: id}),
    do: get_canvas_layout(id)

  @doc "Whether the template's agent setup has moved on since this canvas copied it."
  def agent_config_drift?(%UnstrCanvas{} = canvas, template \\ nil) do
    template = template || agent_source_template(canvas)

    case template do
      %Layout{} = template ->
        canvas.agent_config_source_hash != AgentConfig.hash(template.agent_config)

      _other ->
        false
    end
  end

  @doc """
  Creates or updates a template and replaces its agent files in one transaction.

  The designer saves everything with one button, so a half-saved template would
  leave the prompt and the files disagreeing.
  """
  def save_template_with_agent(nil, user_id, attrs, drafts) do
    Repo.transaction(fn ->
      with {:ok, template} <- create_template(user_id, attrs),
           {:ok, :ok} <- AgentFiles.replace(:template, template.id, drafts) do
        template
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def save_template_with_agent(%Layout{} = template, _user_id, attrs, drafts) do
    Repo.transaction(fn ->
      with {:ok, template} <- update_template(template, attrs),
           {:ok, :ok} <- AgentFiles.replace(:template, template.id, drafts) do
        template
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp broadcast_agent_config(canvas_id) do
    Phoenix.PubSub.broadcast(
      Psc.PubSub,
      pubsub_topic_unstr(canvas_id),
      {:agent_config_updated, canvas_id}
    )
  end

  @doc """
  Delete an unstructured canvas.
  """
  def delete_unstr_canvas(canvas) do
    Repo.delete(canvas)
  end

  @doc """
  Share an unstructured canvas with a user by email.
  """
  def share_unstr_canvas_with(canvas, email) do
    new_shared_with =
      (canvas.shared_with || [])
      |> Enum.uniq()
      |> then(&(&1 ++ [email]))
      |> Enum.uniq()

    canvas
    |> UnstrCanvas.changeset(%{shared_with: new_shared_with})
    |> Repo.update()
  end

  @doc """
  Remove a user's access to an unstructured canvas.
  """
  def unshare_unstr_canvas(canvas, email) do
    new_shared_with =
      canvas.shared_with
      |> Enum.reject(&(&1 == email))

    canvas
    |> UnstrCanvas.changeset(%{shared_with: new_shared_with})
    |> Repo.update()
  end

  @doc """
  Check if a user can access an unstructured canvas (author or shared with them).
  """
  def can_access_unstr_canvas?(canvas, user_email) do
    canvas = Repo.preload(canvas, :author)
    canvas.author.email == user_email || Enum.any?(canvas.shared_with, &(&1 == user_email))
  end

  # Get the next seq number for the given unstr_canvas.
  #
  # Floored at snapshot_seq: events at or below the snapshot are pruned
  # (see save_unstr_canvas_content_to_db/2), so max(seq) alone restarts at 1
  # after pruning and would place new events below the snapshot point,
  # where get_unstr_canvas_content/1 never replays them.
  defp next_unstr_canvas_sequence(canvas_id) do
    max_event_seq =
      Repo.one(
        from(e in Psc.Canvas.UnstrCanvasEvent,
          where: e.unstr_canvas_id == ^canvas_id,
          select: max(e.seq)
        )
      ) || 0

    snapshot_seq =
      Repo.one(from(c in UnstrCanvas, where: c.id == ^canvas_id, select: c.snapshot_seq)) || 0

    max(max_event_seq, snapshot_seq) + 1
  end

  def pubsub_topic_unstr(canvas_id), do: "unstr_canvas:#{canvas_id}"

  def get_unstr_canvas_content(canvas_id) do
    canvas = Repo.get!(UnstrCanvas, canvas_id)
    cells = canvas.cells || %{}
    snapshot_seq = canvas.snapshot_seq || 0

    events =
      from(e in Psc.Canvas.UnstrCanvasEvent,
        where: e.unstr_canvas_id == ^canvas_id and e.seq > ^snapshot_seq,
        order_by: [asc: e.seq]
      )
      |> Repo.all()

    Enum.reduce(events, cells, &Psc.Canvas.UnstrCanvasCRDT.apply_operation/2)
  end

  def apply_unstr_canvas_operation(canvas_id, user_id, operation) do
    seq = next_unstr_canvas_sequence(canvas_id)

    event_attrs = %{
      operation: operation,
      seq: seq,
      unstr_canvas_id: canvas_id,
      user_id: user_id
    }

    case Repo.insert(
           Psc.Canvas.UnstrCanvasEvent.changeset(%Psc.Canvas.UnstrCanvasEvent{}, event_attrs)
         ) do
      {:ok, _event} ->
        Phoenix.PubSub.broadcast(
          Psc.PubSub,
          pubsub_topic_unstr(canvas_id),
          {:operation, user_id, operation, seq}
        )

        {:ok, seq}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Apply operation and broadcast with a per-client id.
  """
  def apply_unstr_canvas_operation(canvas_id, user_id, client_id, operation) do
    seq = next_unstr_canvas_sequence(canvas_id)

    event_attrs = %{
      operation: operation,
      seq: seq,
      unstr_canvas_id: canvas_id,
      user_id: user_id
    }

    case Repo.insert(
           Psc.Canvas.UnstrCanvasEvent.changeset(%Psc.Canvas.UnstrCanvasEvent{}, event_attrs)
         ) do
      {:ok, _event} ->
        Phoenix.PubSub.broadcast(
          Psc.PubSub,
          pubsub_topic_unstr(canvas_id),
          {:operation, user_id, client_id, operation, seq}
        )

        {:ok, seq}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def save_unstr_canvas_content_to_db(canvas_id, cells) do
    case get_unstr_canvas(canvas_id) do
      nil ->
        {:error, :not_found}

      canvas ->
        # Floored at the stored snapshot_seq for the same reason as
        # next_unstr_canvas_sequence/1: events at or below it are already pruned,
        # so a save with no pending events sees max(seq) = nil and would otherwise
        # write 0 back over the marker.
        max_seq =
          max(
            Repo.one(
              from(e in Psc.Canvas.UnstrCanvasEvent,
                where: e.unstr_canvas_id == ^canvas_id,
                select: max(e.seq)
              )
            ) || 0,
            canvas.snapshot_seq || 0
          )

        result =
          canvas
          |> UnstrCanvas.changeset(%{cells: cells, snapshot_seq: max_seq})
          |> Repo.update(stale_error_field: :base)

        # Prune events already folded into the snapshot. The snapshot fully
        # captures state through max_seq and loading replays only seq >
        # snapshot_seq, so pruned rows are dead weight. This keeps the event
        # table small (free-tier Postgres is limited to 10k rows per table). Only
        # prune once the marker is durably stored, so a failed update can never
        # drop events that are not yet represented in the saved snapshot.
        with {:ok, _canvas} <- result do
          Repo.delete_all(
            from(e in Psc.Canvas.UnstrCanvasEvent,
              where: e.unstr_canvas_id == ^canvas_id and e.seq <= ^max_seq
            )
          )
        end

        result
    end
  end

  @doc """
  Delete canvas events already folded into the saved `cells`.

  The counterpart to `Documents.sweep_folded_events/0` for canvases: pruning
  only happens on save, so canvases abandoned before their first save keep
  their event tail forever. Returns the number of deleted rows.
  """
  def sweep_folded_events do
    {deleted, _} =
      Repo.delete_all(
        from(e in Psc.Canvas.UnstrCanvasEvent,
          join: c in UnstrCanvas,
          on: c.id == e.unstr_canvas_id,
          where: e.seq <= c.snapshot_seq
        )
      )

    deleted
  end
end
