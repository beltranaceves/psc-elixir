// Bento board geometry.
//
// A card is placed on a fixed column grid by its cell's "placement". Dragging
// or resizing previews the new rectangle locally and, on release, pushes one
// `move_card` / `resize_card` for the LiveView to apply. One operation per
// gesture keeps the event log short: a drag that ends where it started sends
// nothing at all.
//
// The server stays authoritative: it clamps the rectangle and broadcasts the
// operation, so every client (including this one) converges on the same board.
const PREVIEW_ATTR = "data-bento-preview"

// The board is drawn with two CSS tracks per column (or row unit), so a card
// can be resized by half a column without changing the template's grid.
const TRACKS_PER_UNIT = 2
const MIN_SIZE = 1 / TRACKS_PER_UNIT

export default {
  mounted() {
    this.columns = this.boardColumns()
    this.card = null
    this.mode = null
    this.start = null
    this.origin = null
    this.preview = null

    this.onPointerDown = event => this.startGesture(event)
    this.onPointerMove = event => this.moveGesture(event)
    this.onPointerUp = () => this.endGesture()
    this.onKeyDown = event => this.keyGesture(event)

    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("keydown", this.onKeyDown)
    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("pointercancel", this.onPointerUp)
  },

  // The server is the only writer of the grid; after a patch (a new column
  // count from the toolbar, or the render that follows a drag) the cached
  // count and the locally grown template must both follow it.
  updated() {
    this.columns = this.boardColumns()
    this.grewTo = null
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("keydown", this.onKeyDown)
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("pointercancel", this.onPointerUp)
    this.clearPreview()
  },

  startGesture(event) {
    const drag = event.target.closest("[data-bento-drag]")
    const resize = event.target.closest("[data-bento-resize]")
    if (!drag && !resize) return

    const card = event.target.closest("[id^='bento-card-']")
    if (!card) return

    event.preventDefault()
    this.card = card
    this.mode = drag ? "move" : "resize"
    this.start = { x: event.clientX, y: event.clientY }
    this.origin = this.readPlacement(card)
    this.preview = null
    // Read the grid at the start of every gesture: the toolbar's NxM inputs
    // can change it while the board is on screen.
    this.columns = this.boardColumns()
    this.units = this.measureUnits()
    this.baseTemplate = this.el.style.gridTemplateColumns
    this.grewTo = null
    this.markPreview()
  },

  moveGesture(event) {
    if (!this.card) return
    event.preventDefault()

    const dx = (event.clientX - this.start.x) / this.units.x
    const dy = (event.clientY - this.start.y) / this.units.y

    // A card can be dragged past the current right edge: the board grows with
    // it, the way a card dragged down grows the board's rows. The cap is the
    // widest grid the model allows.
    const maxColumns = this.maxColumns()

    const next =
      this.mode === "move"
        ? {
            // The same half-unit step a resize uses, so a card can be nudged
            // half a column without changing its size first.
            x: clamp(snap(this.origin.x + dx), 0, maxColumns - this.origin.w),
            y: Math.max(0, snap(this.origin.y + dy)),
            w: this.origin.w,
            h: this.origin.h,
          }
        : {
            x: this.origin.x,
            y: this.origin.y,
            // Half-column steps: the pointer has to travel half a column
            // before the card grows.
            w: clamp(snap(this.origin.w + dx), MIN_SIZE, maxColumns - this.origin.x),
            h: Math.max(MIN_SIZE, snap(this.origin.h + dy)),
          }

    this.preview = next
    this.applyPreview(next)
  },

  endGesture() {
    if (!this.card) return

    const card = this.card
    const mode = this.mode
    const origin = this.origin
    const placement = this.preview

    const moved = placement && (placement.x !== origin.x || placement.y !== origin.y)
    const resized = placement && (placement.w !== origin.w || placement.h !== origin.h)
    const pushes = Boolean(placement) && (mode === "move" ? moved : resized)

    // Drop the local grid growth: the server renders the board it stored. A
    // gesture that sends nothing restores the grid the server already had.
    if (!pushes) this.restoreGrid()
    this.clearPreview()
    this.card = null
    this.mode = null
    this.start = null
    this.preview = null

    if (!pushes) return

    const cellKey = card.id.replace("bento-card-", "")

    if (mode === "move") {
      this.pushEvent("move_card", { cell_key: cellKey, x: placement.x, y: placement.y })
    } else {
      this.pushEvent("resize_card", { cell_key: cellKey, w: placement.w, h: placement.h })
    }
  },

  // Shift + arrow resizes. The LiveView keydown payload carries only `key`
  // (Phoenix does not forward the modifier flags), so the resize path has to
  // read `shiftKey` here and push the finished rectangle itself. Plain arrows
  // keep going to the server's `phx-keydown`, which moves the card one unit.
  keyGesture(event) {
    if (!event.shiftKey) return

    const grip = event.target.closest("[data-bento-drag]")
    if (!grip) return

    const card = grip.closest("[id^='bento-card-']")
    if (!card) return

    const delta = KEY_DELTAS[event.key]
    if (!delta) return

    const placement = this.readPlacement(card)
    const maxColumns = this.maxColumns()

    event.preventDefault()
    event.stopPropagation()

    this.pushEvent("resize_card", {
      cell_key: card.id.replace("bento-card-", ""),
      w: clamp(placement.w + delta.x * MIN_SIZE, MIN_SIZE, maxColumns - placement.x),
      h: Math.max(MIN_SIZE, placement.h + delta.y * MIN_SIZE),
    })
  },

  // The grid's own measurements: the distance between two column starts and
  // between two row starts, including the gap.
  measureUnits() {
    const styles = window.getComputedStyle(this.el)
    const gap = parseFloat(styles.columnGap) || 0
    const rowGap = parseFloat(styles.rowGap) || 0
    const columns = Math.max(this.columns, 1)
    const width = this.el.clientWidth - gap * (columns - 1)
    const column = width / columns
    // One row unit is two tracks of half height.
    const row = (parseFloat(styles.gridAutoRows) || 36) * TRACKS_PER_UNIT

    return { x: column + gap, y: row + rowGap }
  },

  readPlacement(card) {
    const style = window.getComputedStyle(card)
    const [, columnStart] = style.gridColumnStart.split(" / ")
    const columnEnd = style.gridColumnEnd.replace("span ", "")
    const [, rowStart] = style.gridRowStart.split(" / ")
    const rowEnd = style.gridRowEnd.replace("span ", "")

    return {
      x: (Number(columnStart || style.gridColumnStart) - 1) / TRACKS_PER_UNIT,
      y: (Number(rowStart || style.gridRowStart) - 1) / TRACKS_PER_UNIT,
      w: Number(columnEnd) / TRACKS_PER_UNIT,
      h: Number(rowEnd) / TRACKS_PER_UNIT,
    }
  },

  markPreview() {
    this.card.setAttribute(PREVIEW_ATTR, "true")
    this.card.style.opacity = "0.85"
  },

  applyPreview(placement) {
    if (!this.card) return

    // Growing the grid live keeps the card inside real tracks instead of
    // implicit ones; the cap is the model's maximum.
    const needed = Math.max(this.columns, ceil(placement.x + placement.w))

    if (needed !== this.columns && needed <= this.maxColumns()) {
      this.grewTo = this.grewTo || this.columns
      this.columns = needed
      this.el.style.gridTemplateColumns = `repeat(${needed * TRACKS_PER_UNIT}, minmax(0, 1fr))`
    }

    this.card.style.gridColumn = `${round(placement.x * TRACKS_PER_UNIT) + 1} / span ${round(placement.w * TRACKS_PER_UNIT)}`
    this.card.style.gridRow = `${round(placement.y * TRACKS_PER_UNIT) + 1} / span ${round(placement.h * TRACKS_PER_UNIT)}`
  },

  boardColumns() {
    return Number(this.el.dataset.columns) || 12
  },

  maxColumns() {
    return Number(this.el.dataset.maxColumns) || Math.max(this.boardColumns(), 16)
  },

  // Give the grid back to the server's render when a gesture sends nothing.
  restoreGrid() {
    if (!this.grewTo) return
    this.el.style.gridTemplateColumns = this.baseTemplate || ""
    this.columns = this.boardColumns()
    this.grewTo = null
  },

  clearPreview() {
    if (!this.card) return
    this.card.removeAttribute(PREVIEW_ATTR)
    this.card.style.opacity = ""
  },
}

const KEY_DELTAS = {
  ArrowLeft: { x: -1, y: 0 },
  ArrowRight: { x: 1, y: 0 },
  ArrowUp: { x: 0, y: -1 },
  ArrowDown: { x: 0, y: 1 },
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function round(value) {
  return Math.round(value)
}

function ceil(value) {
  return Math.ceil(value)
}

// Half-column steps, with no floating-point drift.
function snap(value) {
  return Math.round(value * TRACKS_PER_UNIT) / TRACKS_PER_UNIT
}
