# Template designer

## Overview

The template designer lets users define **reusable templates** and share them across users. A template captures the full structure of a canvas: grid dimensions, per-cell metadata (label, semantics, content fields), and relations between cells. Templates are the instantiation source for canvases — when a user creates a canvas from a template, the template's structure is copied into the canvas's `cells` map.

> **Terminology.** A **canvas** is one configurable workspace; a **template** is the reusable structure a canvas is created from. In code these are the `unstr_canvases` and `canvas_layouts` tables (`Psc.Canvas.UnstrCanvas`, `Psc.Canvas.Layout`), the surfaces are `PscWeb.CanvasLayoutLive` (this template designer) and `PscWeb.UnstrCanvasLive` (the canvas editor), and the routes are `/templates` and `/canvases`.

### Design principle

The Ecto entity is intentionally **flexible** (`:map` columns). The template stores its entire definition as a map, so the template designer UI can support arbitrary grid sizes and cell configurations without schema migrations. The editor (see `canvas-editor.md`) decodes the same map structure at runtime — it is structure-agnostic and renders whatever the template defines.

## Design System

### Vibe

**"Calm analytical workspace"** — think Notion meets a research whiteboard. Focused, quiet, generous whitespace, no visual noise. The canvas is the hero; chrome recedes. The user is in a flow state of analysis and synthesis, not a flow state of "operating a tool."

### Color

- **Dark-first.** Deep neutral background (warm charcoal, not pure black).
- **One accent color** (indigo/violet) reserved for interactive elements and active states. No competing colors.
- **Presence colors** (for multi-user indicators) are a separate small palette — green, amber, cyan, pink — assigned per user.
- All colors from the daisyUI theme variables are replaced with custom properties on `:root`.

### Typography

- System font stack: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`.
- Cell labels: 12–13px, semibold, slight letter-spacing, uppercase or title case depending on context.
- Cell content: 14–15px, comfortable line-height (1.5).
- Page titles: 18–20px, semibold.
- No decorative fonts. No monospace except for IDs/keys.

### Spacing

- 8px base grid.
- Cards: 16px padding, 12px gap between cells.
- The grid breathes — no cramped cells.
- Sidebar: fixed 280px, collapsible.

### Elevation

- Flat with subtle borders (1px, low-opacity white).
- No drop shadows on cards.
- Presence indicators use color, not elevation.
- Focus states use a 2px accent outline, not shadows.

### Motion

- 150–200ms ease-out transitions.
- Cell focus: subtle 1.01 scale.
- Presence indicators: fade in/out.
- No bouncy or playful motion.

### Component Mapping

| UI Element | SaladUI Component | Notes |
|---|---|---|
| Template card | `<.card>` | Header = name + dimensions badge |
| "Use template" button | `<.button variant="primary">` | Compact size |
| Designer grid cells | `<.card>` with custom header | Label in header, fields in body |
| Cell field inputs | `<.textarea>` | Auto-resizing, no visible border until focused |
| Structure-editing controls | `<.button variant="outline" size="sm">` | Add row/column, remove × |
| Relations list | `<.badge>` + text | From → To with label |
| Sidebar (presence + sharing) | `<.sidebar>` or custom panel | Fixed right side |
| Presence indicator | Colored dot + name tooltip | Custom CSS, `<.tooltip>` for hover |
| Share form | `<.input>` + `<.button>` | Inline, compact |
| Template dropdown | `<.select>` | In create form |
| Delete confirmation | `<.alert_dialog>` | Destructive action |
| Loading state | `<.skeleton>` | While canvas loads |
| Empty state | `<.alert>` | "No templates yet" / "No canvases yet" |
| Tabs (My / Shared) | `<.tabs>` | In library and editor sidebar |

**Not used in MVP:** chart, pagination, breadcrumb, accordion, command, slider, switch, radio_group, toggle_group, hover_card, menu, popover, sheet.

### Screenshot Review Loop

Specs and implementations are validated with screenshots. The app is screenshotted in the browser, and the screenshot is analyzed against this design system. Screenshots are the authoritative visual reference.

## Data Model

### Template definition (stored in `canvas_layouts.layout_map`)

The existing `Layout` schema and `canvas_layouts` table are **extended** with two new fields. The table already has `name`, `description`, and `layout_map`.

**New columns on `canvas_layouts`:**

| Column | Type | Purpose |
|--------|------|---------|
| `shared_with` | `{:array, :string}` | Emails of users with access to this template |
| `author_id` | `id` (FK → users) | Template owner |

The `layout_map` field stores the full template definition as a nested map:

```elixir
%{
  "rows" => [
    %{"id" => "r1", "label" => "Rationale"},
    %{"id" => "r2", "label" => "Strategy"}
  ],
  "columns" => [
    %{"id" => "c1", "label" => "Perceive"},
    %{"id" => "c2", "label" => "Form"}
  ],
  "cells" => %{
    "r1_c1" => %{
      "label" => "Problem",
      "semantics" => "problem",       # atom-ish string: "problem" | "solution" | "evidence" | "note" | "free"
      "fields" => ["content"],        # ordered list of field keys for this cell
      "defaults" => %{"content" => ""}
    },
    "r1_c2" => %{
      "label" => "Leverage",
      "semantics" => "solution",
      "fields" => ["technology", "components", "information"],
      "defaults" => %{
        "technology" => "",
        "components" => "",
        "information" => ""
      }
    }
  },
  "relations" => [
    %{"from" => "r1_c1", "to" => "r1_c2", "label" => "leads to"}
  ]
}
```

### Field semantics

| Key | Required | Description |
|-----|----------|-------------|
| `rows` | yes | Ordered list of row definitions. Each has `id` (string, unique) and `label` (display name). |
| `columns` | yes | Ordered list of column definitions. Same shape as rows. |
| `cells` | yes | Map of `"rowid_colid"` → cell metadata. Every grid position **must** have an entry. |
| `relations` | no | Directed edges between cells. `from`/`to` are cell keys; `label` is optional display text. |

### Cell semantics values

The `semantics` field is a simple classification used by the editor for iconography and future insights. Suggested values (extensible, not enforced):

- `"problem"` — a problem statement or challenge
- `"solution"` — a proposed solution or approach
- `"evidence"` — supporting data, references, or justification
- `"note"` — freeform annotation
- `"free"` — no specific semantics; pure user content

### Instantiation

When a canvas is created from a template, the template's `layout_map` is deep-copied into the new canvas's `cells` map. The canvas then owns its own copy — subsequent edits to the template do **not** propagate to existing canvases. This is intentional: canvases are living documents; templates are starting points.

## File Plan

| File | Action | Purpose |
|------|--------|---------|
| `lib/psc/canvas/layout.ex` | **modify** | Add `shared_with` and `author_id` fields to schema; add `shared_with` to changeset |
| `lib/psc/canvas.ex` | **modify** | Add template-specific context functions (see API below) |
| `lib/psc_web/live/canvas_layout_live/index.ex` | **modify** | Add template library UI (list own + shared, instantiate button) |
| `lib/psc_web/live/canvas_layout_live/editor.ex` | **modify** | Extend designer for cell metadata editing + relations |
| `priv/repo/migrations/xxx_add_sharing_to_canvas_layouts.exs` | **create** | Migration: add `shared_with`, `author_id` to `canvas_layouts` |
| `test/psc/canvas_test.exs` | **create** | Unit tests for template CRUD + sharing + instantiation |
| `test/psc_web/live/canvas_layout_live_test.exs` | **modify** | Add tests for cell metadata editing, relations, instantiation |

## API (Context functions)

All functions go in `Psc.Canvas` alongside the existing layout CRUD.

### Listing and fetching

```elixir
list_templates(user) :: [Layout]
# Returns templates authored by user OR shared with user's email.
# Ordered by updated_at desc.

get_template(id) :: Layout | nil
# Standard fetch.

get_template_with_author(id) :: Layout | nil
# Preloads author.
```

### CRUD

```elixir
create_template(user_id, attrs) :: {:ok, Layout} | {:error, Changeset}
# Wraps existing create_canvas_layout/1 but assigns author_id from user_id.

update_template(template, attrs) :: {:ok, Layout} | {:error, Changeset}
# Wraps existing update_canvas_layout/2.

delete_template(template) :: {:ok, Layout} | {:error, Changeset}
# Wraps existing delete_canvas_layout/1.
```

### Sharing

```elixir
share_template_with(template, email) :: {:ok, Layout} | {:error, Changeset}
# Appends email to shared_with (idempotent; no duplicates).

unshare_template(template, email) :: {:ok, Layout} | {:error, Changeset}
# Removes email from shared_with.

can_access_template?(template, user_email) :: boolean
# true if user_email == author.email OR user_email in shared_with.
```

### Instantiation

```elixir
instantiate_template(template, user_id) :: {:ok, UnstrCanvas} | {:error, Changeset}
# 1. Deep-copies template.layout_map into a new cells map.
# 2. Creates an UnstrCanvas with author_id=user_id, name=template.name (or "Untitled"),
#    cells=copied_map, snapshot_seq=0.
# 3. Returns the created canvas.
```

## UI Behavior

### Template library (`/canvas-layouts`)

**Index page** shows two sections:
- **My templates** — templates where `author_id == current_user.id`
- **Shared with me** — templates where `current_user.email` is in `shared_with`

Each template card shows: name, description, grid dimensions (e.g., "3 × 4"), cell count, and a **"Use template"** button that calls `instantiate_template` and navigates to the new canvas editor.

**Create template** button opens the designer with an empty 2×2 grid.

**Delete** button on own templates (with confirmation dialog).

### Template designer (`/canvas-layouts/new` and `/canvas-layouts/:id`)

The existing `CanvasLayoutLive.Editor` already supports add/remove rows and columns. The designer is extended with:

1. **Cell selection** — clicking a grid cell opens a side panel with:
   - **Label** text input (display name for the cell)
   - **Semantics** dropdown (problem / solution / evidence / note / free)
   - **Fields** — dynamic list of text inputs; add/remove field buttons. Each field key becomes an input in the editor.
   - **Defaults** — for each field, an optional default value

2. **Relations** — a "Add relation" flow:
   - Select source cell, target cell, optional label
   - Relations listed below the designer with delete buttons
   - (Visual arrow rendering on the canvas is **out of scope** for MVP — relations are metadata only)

3. **Save** — validates that every grid position has a cell entry, then persists via `update_template`.

4. **Share** — email input + share button (same pattern as canvas sharing).

### Validation rules

- At least 1 row and 1 column.
- Cell keys must match `"{row_id}_{column_id}"` for every position in the grid.
- Field keys must be unique within a cell.
- Field keys must be valid lowercase strings (alphanumeric + underscore).
- `relations.from` and `relations.to` must reference existing cell keys.

## Acceptance Criteria

- [ ] Create a template with a custom grid size (e.g., 3 rows × 5 columns)
- [ ] Edit a cell's label, semantics, and fields in the designer
- [ ] Add and remove fields within a cell
- [ ] Define a relation between two cells
- [ ] Share a template with another user by email
- [ ] Shared template appears in the other user's "Shared with me" list
- [ ] Instantiate a canvas from a template — the new canvas has the template's grid and cell structure
- [ ] Editing a template after instantiation does **not** affect existing canvases
- [ ] Delete a template (only by author)
- [ ] Validation prevents empty grids, duplicate field keys, and broken relation references

## Out of Scope

- Template versioning or history
- Template categories, tags, or search
- Visual relation arrows / graph overlay on the canvas
- Template import/export (JSON)
- Copying an existing canvas as a template (reverse instantiation)
- Concurrent multi-user editing of templates (CRDT on templates)

## Verification Methods

- **Unit tests** (`test/psc/canvas_test.exs`): template CRUD, sharing, instantiation produces correct `cells` map
- **LiveView tests** (`canvas_layout_live_test.exs`): designer renders grid, cell metadata editing persists, relations save
- **Browser test**: full flow — create template, share, log in as other user, see it in library, instantiate
