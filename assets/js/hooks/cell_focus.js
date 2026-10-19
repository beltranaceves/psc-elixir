// Canvas cell interaction.
//
// Desktop: clicking anywhere in a cell opens the nearest markdown field.
//
// Mobile (<= 639px): the first tap puts the cell full screen so a cramped grid
// cell can be read comfortably. A second tap opens the field for editing, the
// floating button (or Escape) returns to the grid, and swiping horizontally or
// vertically moves to the neighbouring cell.
const MOBILE_QUERY = "(max-width: 639px)"
const SWIPE_THRESHOLD = 44

export default {
  mounted() {
    this.cellKey = this.el.dataset.cellKey || this.el.id.replace("cell-card-", "")
    // Used by neighbouring cells to hand the fullscreen state over.
    this.el._cellFocus = this

    this.handleClick = event => this.onClick(event)
    this.handleKeydown = event => {
      if (event.key === "Escape" && this.isExpanded()) this.collapse()
    }
    this.handlePointerDown = event => this.onPointerDown(event)
    this.handlePointerUp = event => this.onPointerUp(event)

    this.el.addEventListener("click", this.handleClick)
    this.el.addEventListener("pointerdown", this.handlePointerDown)
    this.el.addEventListener("pointerup", this.handlePointerUp)
    document.addEventListener("keydown", this.handleKeydown)
  },

  updated() {
    // LiveView patches can rewrite the class attribute; keep the fullscreen
    // state while the user is inside the cell.
    if (this.expandedByPatch && !this.isExpanded()) this.expand()
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    this.el.removeEventListener("pointerdown", this.handlePointerDown)
    this.el.removeEventListener("pointerup", this.handlePointerUp)
    document.removeEventListener("keydown", this.handleKeydown)
    if (this.el._cellFocus === this) delete this.el._cellFocus
    clearTimeout(this.closeTimer)
    this.releaseBody()
  },

  onClick(event) {
    if (event.target.closest("[data-cell-exit]")) {
      event.preventDefault()
      event.stopPropagation()
      this.collapse()
      return
    }

    // A swipe ends with a click; it must not open the editor.
    if (this.suppressClick) {
      this.suppressClick = false
      event.preventDefault()
      return
    }

    if (!window.matchMedia(MOBILE_QUERY).matches) return this.openField(event)

    if (!this.isExpanded()) {
      event.preventDefault()
      this.expand()
      return
    }

    this.openField(event)
  },

  onPointerDown(event) {
    this.startPoint = null
    if (!this.isExpanded()) return
    if (event.target.closest("textarea, input, select, button, a")) return

    this.startPoint = {
      x: event.clientX,
      y: event.clientY,
      scrollTop: this.el.scrollTop,
    }
  },

  onPointerUp(event) {
    const start = this.startPoint
    this.startPoint = null
    if (!start || !this.isExpanded()) return

    const dx = event.clientX - start.x
    const dy = event.clientY - start.y
    if (Math.hypot(dx, dy) < SWIPE_THRESHOLD) return

    const horizontal = Math.abs(dx) > Math.abs(dy)

    // Any deliberate swipe ends with a click event; never treat it as a tap.
    this.suppressClick = true
    setTimeout(() => (this.suppressClick = false), 350)

    // Vertical swipes belong to scrolling when the cell content is taller than
    // the screen; horizontal swipes always navigate.
    if (!horizontal && this.el.scrollHeight > this.el.clientHeight + 4) return

    const delta = horizontal ? (dx < 0 ? 1 : -1) : dy < 0 ? 1 : -1
    this.navigate(horizontal ? "column" : "row", delta)
  },

  // Move the fullscreen state to the cell `delta` steps away on one axis.
  navigate(axis, delta) {
    const td = this.el.closest("td")
    const tr = td && td.parentElement
    const tbody = tr && tr.parentElement
    if (!td || !tr || !tbody) return

    const rows = [...tbody.querySelectorAll("tr")]
    const rowIndex = rows.indexOf(tr)
    const columns = [...tr.querySelectorAll("td")]
    const columnIndex = columns.indexOf(td) - 1
    if (columnIndex < 0) return

    const targetRow = rows[axis === "row" ? rowIndex + delta : rowIndex]
    if (!targetRow) return

    const targetCell = [...targetRow.querySelectorAll("td")][
      (axis === "column" ? columnIndex + delta : columnIndex) + 1
    ]
    const target = targetCell && targetCell.querySelector(".canvas-cell")
    if (!target || target === this.el || !target._cellFocus) return

    this.collapse({ instant: true })
    target._cellFocus.expand()
  },

  isExpanded() {
    return this.el.classList.contains("is-expanded")
  },

  expand() {
    document.querySelectorAll(".canvas-cell.is-expanded").forEach(cell => {
      if (cell !== this.el) cell.classList.remove("is-expanded", "is-closing")
    })

    this.el.classList.remove("is-closing")
    this.el.classList.add("is-expanded")
    this.expandedByPatch = true
    document.body.classList.add("overflow-hidden")
    this.el.scrollTop = 0
  },

  collapse({ instant = false } = {}) {
    if (!this.isExpanded()) return

    this.expandedByPatch = false

    if (instant) {
      this.finishCollapse()
    } else {
      // Play the exit animation, then drop the fullscreen class.
      this.el.classList.add("is-closing")
      this.closeTimer = setTimeout(() => {
        this.el.classList.remove("is-closing")
        this.finishCollapse()
      }, 140)
    }

    // Closing the fullscreen view also ends editing.
    if (document.activeElement && this.el.contains(document.activeElement)) {
      document.activeElement.blur()
    }
  },

  finishCollapse() {
    this.el.classList.remove("is-expanded")
    this.releaseBody()
  },

  releaseBody() {
    if (document.querySelectorAll(".canvas-cell.is-expanded").length === 0) {
      document.body.classList.remove("overflow-hidden")
    }
  },

  openField(event) {
    if (event.target.closest("textarea, input, select, button, a")) return

    const openField = wrapper => {
      const display = wrapper && wrapper.querySelector(".md-render")
      // A hidden display means the field is already open for editing.
      if (display && !display.classList.contains("hidden")) display.click()
    }

    const inside = event.target.closest("[data-field-wrapper]")
    if (inside) return openField(inside)

    const wrappers = [...this.el.querySelectorAll("[data-field-wrapper]")]
    if (wrappers.length === 0) return

    const nearest = wrappers.reduce((best, wrapper) => {
      const rect = wrapper.getBoundingClientRect()
      const distance = Math.abs((rect.top + rect.bottom) / 2 - event.clientY)
      return !best || distance < best.distance ? { wrapper, distance } : best
    }, null)

    openField(nearest.wrapper)
  },
}