defmodule PscWeb.Components.ImageBoard do
  @moduledoc """
  The frame of an image board: the backdrop picture with its floating cells
  positioned over it.

  The frame is shared by the canvas editor and the designer so the picture,
  its shape and the cells' percentage geometry cannot drift between the two.
  What a cell *contains* differs - a canvas cell edits values, a designer cell
  edits the definition - so the caller supplies that through the `:cell` slot.

  Cells are absolutely positioned in percent of the frame, which is why the
  same stored placement keeps its spot on any screen and on any size of
  picture. `ImageBoard` (the JS hook) reads those percentages back while a cell
  is dragged or resized.
  """

  use Phoenix.Component

  alias Psc.Canvas.Structure

  @doc """
  The shape presets the backdrop control offers.

  `"auto"` lets the picture set the board's shape; every other option pins an
  aspect ratio so the board keeps a stable frame while the picture is fitted
  inside it.
  """
  def aspect_options do
    [
      {"auto", "Picture's shape"},
      {"16:9", "16 : 9"},
      {"4:3", "4 : 3"},
      {"3:2", "3 : 2"},
      {"1:1", "Square"},
      {"9:16", "Portrait"}
    ]
  end

  @doc "The ratio behind a shape preset, or `nil` for the picture's own shape."
  def aspect_value("16:9"), do: 16 / 9
  def aspect_value("4:3"), do: 4 / 3
  def aspect_value("3:2"), do: 3 / 2
  def aspect_value("1:1"), do: 1.0
  def aspect_value("9:16"), do: 9 / 16
  def aspect_value(_key), do: nil

  @doc "The preset a stored aspect ratio corresponds to, for a select's value."
  def aspect_key(aspect) when is_number(aspect) do
    rounded = Float.round(aspect, 2)

    Enum.find_value(aspect_options(), "auto", fn {key, _label} ->
      case aspect_value(key) do
        nil -> nil
        value -> if Float.round(value, 2) == rounded, do: key
      end
    end)
  end

  def aspect_key(_aspect), do: "auto"

  @doc """
  The attributes the `set_backdrop` form submits, in the shape
  `Psc.Canvas.Structure.set_backdrop/2` expects.
  """
  def backdrop_attrs(params) do
    attrs = %{"url" => params["url"] || "", "fit" => params["fit"], "alt" => params["alt"]}

    case params["aspect"] do
      nil -> attrs
      "auto" -> Map.put(attrs, "aspect", nil)
      key -> Map.put(attrs, "aspect", aspect_value(key))
    end
  end

  @doc """
  The backdrop fields: the picture's URL, its shape, how it is fitted when the
  shape is pinned, and its description.

  Both the canvas and the designer render this form; the `set_backdrop` event
  it emits is handled by each, and `Psc.Canvas.Structure` validates the values
  before storing them.
  """
  attr :cells, :map, required: true
  attr :can_edit?, :boolean, default: true
  attr :id_prefix, :string, default: "image-backdrop"

  def backdrop_controls(assigns) do
    backdrop = Structure.backdrop(assigns.cells)

    assigns =
      assign(assigns,
        backdrop: backdrop,
        aspects: aspect_options(),
        fits: Structure.backdrop_fits()
      )

    ~H"""
    <form
      id={@id_prefix <> "-form"}
      phx-change="set_backdrop"
      class="flex min-w-0 flex-wrap items-center gap-1.5"
    >
      <input
        type="url"
        name="url"
        id={@id_prefix <> "-url"}
        value={@backdrop.url}
        disabled={!@can_edit?}
        phx-debounce="600"
        placeholder="Picture or SVG URL"
        aria-label="Backdrop picture URL"
        title="A picture or SVG URL: https://, /path or a data:image URI"
        class="h-8 min-w-0 flex-1 basis-48 rounded-md border border-base-content/15 bg-base-100 px-2 text-xs text-base-content placeholder-base-content/40 focus:border-primary focus:outline-none disabled:opacity-60 sm:basis-64"
      />
      <select
        name="aspect"
        id={@id_prefix <> "-aspect"}
        disabled={!@can_edit?}
        phx-debounce="300"
        aria-label="Backdrop shape"
        title="The board's shape. The picture's own shape follows the image."
        class="h-8 rounded-md border border-base-content/15 bg-base-100 px-1.5 text-xs text-base-content focus:border-primary focus:outline-none disabled:opacity-60"
      >
        <option
          :for={{key, label} <- @aspects}
          value={key}
          selected={aspect_key(@backdrop.aspect) == key}
        >
          {label}
        </option>
      </select>

      <select
        name="fit"
        id={@id_prefix <> "-fit"}
        disabled={!@can_edit?}
        phx-debounce="300"
        aria-label="How the picture fits the shape"
        title="How the picture fills a pinned shape"
        class="h-8 rounded-md border border-base-content/15 bg-base-100 px-1.5 text-xs text-base-content focus:border-primary focus:outline-none disabled:opacity-40"
      >
        <option :for={fit <- @fits} value={fit} selected={@backdrop.fit == fit}>{fit}</option>
      </select>

      <input
        type="text"
        name="alt"
        id={@id_prefix <> "-alt"}
        value={@backdrop.alt}
        disabled={!@can_edit?}
        phx-debounce="400"
        placeholder="Describe the picture"
        aria-label="Backdrop description"
        class="h-8 min-w-0 basis-40 rounded-md border border-base-content/15 bg-base-100 px-2 text-xs text-base-content placeholder-base-content/40 focus:border-primary focus:outline-none disabled:opacity-60"
      />
      <p class="w-full text-[0.65rem] leading-4 text-base-content/45">
        Paste a picture URL (<code>https://…</code>), a site path (<code>/images/…</code>) or a
        <code>data:image</code>
        URI (percent-encoded). SVG, PNG, JPEG and WebP all work.
      </p>
    </form>
    """
  end

  attr :cells, :map, required: true
  attr :board_id, :string, required: true
  attr :class, :any, default: nil

  slot :cell, required: true

  def board(assigns) do
    backdrop = Structure.backdrop(assigns.cells)

    assigns =
      assigns
      |> assign(:backdrop, backdrop)
      |> assign(:cards, Structure.cards(assigns.cells))

    ~H"""
    <div
      id={@board_id}
      phx-hook="ImageBoard"
      data-image-board
      class={[
        "image-board relative w-full overflow-hidden rounded-xl border border-base-content/20 bg-base-200",
        @class
      ]}
      style={Structure.image_board_style(@cells)}
    >
      <img
        :if={@backdrop.url}
        src={@backdrop.url}
        alt={@backdrop.alt || ""}
        draggable="false"
        class={image_class(@backdrop)}
      />
      <div
        :if={!@backdrop.url}
        class="absolute inset-0 flex flex-col items-center justify-center gap-1 border border-dashed border-base-content/20 bg-base-200/60 p-4 text-center"
      >
        <span class="text-sm font-medium text-base-content/60">No backdrop yet</span>
        <span class="text-xs text-base-content/45">
          Add a picture or SVG URL, then place cells on top of it.
        </span>
      </div>

      <div
        :for={card <- @cards}
        id={"image-cell-" <> card.key}
        data-image-cell
        data-image-size={Structure.image_size_label(card.w, card.h)}
        title={"Cell placement: #{Structure.image_size_label(card.w, card.h)} of the picture"}
        class="image-cell absolute"
        style={Structure.image_placement_style(card)}
      >
        {render_slot(@cell, card)}
      </div>
    </div>
    """
  end

  @doc """
  The picture's own CSS.

  Without a pinned aspect the picture is in the flow and gives the board its
  height; with one the board has that shape and the picture is fitted inside
  it. Either way the picture is not a pointer target: dragging over it must
  reach the cells and the board.
  """
  def image_class(backdrop) do
    if backdrop.aspect do
      [
        "pointer-events-none absolute inset-0 size-full select-none",
        fit_class(backdrop.fit)
      ]
    else
      "pointer-events-none block h-auto w-full select-none"
    end
  end

  defp fit_class("cover"), do: "object-cover"
  defp fit_class("stretch"), do: "object-fill"
  defp fit_class(_fit), do: "object-contain"
end
