// Image board geometry.
//
// A cell is placed on the backdrop picture by percentages: `left`, `top`,
// `width` and `height` are read straight from the cell's inline style. Dragging
// or resizing previews the new rectangle locally and, on release, pushes one
// `move_card` / `resize_card` for the LiveView to apply. One operation per
// gesture keeps the event log short: a gesture that ends where it started
// sends nothing at all.
//
// The server stays authoritative: `Psc.Canvas.Structure` clamps the rectangle
// into the picture and broadcasts the operation, so every client (including
// this one) converges on the same board.
const TRACKS_PER_UNIT = 2
const MIN_SIZE = 2
const EXTENT = 100

const KEY_DELTAS = {
  ArrowLeft: { x: -1, y: 0 },
  ArrowRight: { x: 1, y: 0 },
  ArrowUp: { x: 0, y: -1 },
  ArrowDown: { x: 0, y: 1 },
}

export default {
  mounted() {
    this.cell = null
    this.mode = null
    this.start = null
    this.origin = null
    this.preview = null
    this.rect = null

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

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("keydown", this.onKeyDown)
    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("pointercancel", this.onPointerUp)
    this.clearPreview()
  },

  startGesture(event) {
    const drag = event.target.closest("[data-image-drag]")
    const resize = event.target.closest("[data-image-resize]")
    if (!drag && !resize) return

    const cell = event.target.closest("[data-image-cell]")
    if (!cell) return

    event.preventDefault()
    this.cell = cell
    this.mode = drag ? "move" : "resize"
    this.start = { x: event.clientX, y: event.clientY }
    this.origin = this.readPlacement(cell)
    this.preview = null
    // Measure at the start of every gesture: the picture may have loaded (or
    // the window resized) since the board was rendered.
    this.rect = this.el.getBoundingClientRect()
    cell.style.opacity = "0.85"
  },

  moveGesture(event) {
    if (!this.cell) return
    event.preventDefault()

    const width = Math.max(this.rect.width, 1)
    const height = Math.max(this.rect.height, 1)
    const dx = ((event.clientX - this.start.x) / width) * EXTENT
    const dy = ((event.clientY - this.start.y) / height) * EXTENT

    const next =
      this.mode === "move"
        ? {
            x: clamp(snap(this.origin.x + dx), 0, EXTENT - this.origin.w),
            y: clamp(snap(this.origin.y + dy), 0, EXTENT - this.origin.h),
            w: this.origin.w,
            h: this.origin.h,
          }
        : {
            x: this.origin.x,
            y: this.origin.y,
            w: clamp(snap(this.origin.w + dx), MIN_SIZE, EXTENT - this.origin.x),
            h: clamp(snap(this.origin.h + dy), MIN_SIZE, EXTENT - this.origin.y),
          }

    this.preview = next
    this.applyPreview(next)
  },

  endGesture() {
    if (!this.cell) return

    const cell = this.cell
    const mode = this.mode
    const origin = this.origin
    const placement = this.preview

    const moved = placement && (placement.x !== origin.x || placement.y !== origin.y)
    const resized = placement && (placement.w !== origin.w || placement.h !== origin.h)
    const pushes = Boolean(placement) && (mode === "move" ? moved : resized)

    this.clearPreview()
    this.cell = null
    this.mode = null
    this.start = null
    this.preview = null

    if (!pushes) return

    const cellKey = cell.id.replace("image-cell-", "")

    if (mode === "move") {
      this.pushEvent("move_card", { cell_key: cellKey, x: placement.x, y: placement.y })
    } else {
      this.pushEvent("resize_card", { cell_key: cellKey, w: placement.w, h: placement.h })
    }
  },

  // Shift + arrow resizes. The LiveView keydown payload carries only `key`
  // (Phoenix does not forward the modifier flags), so the resize path reads
  // `shiftKey` here and pushes the finished rectangle itself. Plain arrows
  // keep going to the server's `phx-keydown`, which moves the cell one step.
  keyGesture(event) {
    if (!event.shiftKey) return

    const grip = event.target.closest("[data-image-drag]")
    if (!grip) return

    const cell = grip.closest("[data-image-cell]")
    if (!cell) return

    const delta = KEY_DELTAS[event.key]
    if (!delta) return

    const placement = this.readPlacement(cell)
    const step = 1 / TRACKS_PER_UNIT

    event.preventDefault()
    event.stopPropagation()

    this.pushEvent("resize_card", {
      cell_key: cell.id.replace("image-cell-", ""),
      w: clamp(placement.w + delta.x * step, MIN_SIZE, EXTENT - placement.x),
      h: clamp(placement.h + delta.y * step, MIN_SIZE, EXTENT - placement.y),
    })
  },

  // Coordinates are stored in percent, so the inline style is the source of
  // truth; the browser would only report the resolved pixel rectangle.
  readPlacement(cell) {
    return {
      x: parseFloat(cell.style.left) || 0,
      y: parseFloat(cell.style.top) || 0,
      w: parseFloat(cell.style.width) || 0,
      h: parseFloat(cell.style.height) || 0,
    }
  },

  applyPreview(placement) {
    if (!this.cell) return
    this.cell.style.left = `${placement.x}%`
    this.cell.style.top = `${placement.y}%`
    this.cell.style.width = `${placement.w}%`
    this.cell.style.height = `${placement.h}%`
  },

  clearPreview() {
    if (!this.cell) return
    this.cell.style.opacity = ""
  },
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

// Half-percent steps, with no floating-point drift.
function snap(value) {
  return Math.round(value * TRACKS_PER_UNIT) / TRACKS_PER_UNIT
}
