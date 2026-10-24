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

export default {
  mounted() {
    this.columns = Number(this.el.dataset.columns) || 12
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
    this.units = this.measureUnits()
    this.markPreview()
  },

  moveGesture(event) {
    if (!this.card) return
    event.preventDefault()

    const dx = Math.round((event.clientX - this.start.x) / this.units.x)
    const dy = Math.round((event.clientY - this.start.y) / this.units.y)

    const next =
      this.mode === "move"
        ? {
            x: clamp(this.origin.x + dx, 0, this.columns - this.origin.w),
            y: Math.max(0, this.origin.y + dy),
            w: this.origin.w,
            h: this.origin.h,
          }
        : {
            x: this.origin.x,
            y: this.origin.y,
            w: clamp(this.origin.w + dx, 1, this.columns - this.origin.x),
            h: Math.max(1, this.origin.h + dy),
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

    this.clearPreview()
    this.card = null
    this.mode = null
    this.start = null
    this.preview = null

    if (!placement) return

    const moved = placement.x !== origin.x || placement.y !== origin.y
    const resized = placement.w !== origin.w || placement.h !== origin.h
    if (mode === "move" && !moved) return
    if (mode === "resize" && !resized) return

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
    const columns = Number(this.el.dataset.columns) || this.columns

    event.preventDefault()
    event.stopPropagation()

    this.pushEvent("resize_card", {
      cell_key: card.id.replace("bento-card-", ""),
      w: clamp(placement.w + delta.x, 1, columns - placement.x),
      h: Math.max(1, placement.h + delta.y),
    })
  },

  // The grid's own measurements: the distance between two column starts and
  // between two row starts, including the gap.
  measureUnits() {
    const styles = window.getComputedStyle(this.el)
    const gap = parseFloat(styles.columnGap) || 0
    const rowGap = parseFloat(styles.rowGap) || 0
    const width = this.el.clientWidth - gap * (this.columns - 1)
    const column = width / this.columns
    const row = parseFloat(styles.gridAutoRows) || 72

    return { x: column + gap, y: row + rowGap }
  },

  readPlacement(card) {
    const style = window.getComputedStyle(card)
    const [, columnStart] = style.gridColumnStart.split(" / ")
    const columnEnd = style.gridColumnEnd.replace("span ", "")
    const [, rowStart] = style.gridRowStart.split(" / ")
    const rowEnd = style.gridRowEnd.replace("span ", "")

    return {
      x: Number(columnStart || style.gridColumnStart) - 1,
      y: Number(rowStart || style.gridRowStart) - 1,
      w: Number(columnEnd),
      h: Number(rowEnd),
    }
  },

  markPreview() {
    this.card.setAttribute(PREVIEW_ATTR, "true")
    this.card.style.opacity = "0.85"
  },

  applyPreview(placement) {
    if (!this.card) return
    this.card.style.gridColumn = `${placement.x + 1} / span ${placement.w}`
    this.card.style.gridRow = `${placement.y + 1} / span ${placement.h}`
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
