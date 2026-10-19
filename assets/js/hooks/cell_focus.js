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
    // Capture phase: it must run before the markdown display's own click
    // listener, which would otherwise open the editor on the first tap.
    this.handleCaptureClick = event => this.onCaptureClick(event)
    this.handleKeydown = event => {
      if (event.key === "Escape" && this.isExpanded()) this.collapse()
    }
    this.handlePointerDown = event => {
      if (event.pointerType !== "touch") this.startSwipe(event)
    }
    this.handlePointerUp = event => {
      if (event.pointerType !== "touch") this.finishSwipe(event)
    }
    this.handleTouchStart = event => this.startSwipe(event)
    this.handleTouchEnd = event => this.finishSwipe(event)

    this.el.addEventListener("click", this.handleCaptureClick, true)
    this.el.addEventListener("click", this.handleClick)
    this.el.addEventListener("pointerdown", this.handlePointerDown)
    this.el.addEventListener("pointerup", this.handlePointerUp)
    this.el.addEventListener("touchstart", this.handleTouchStart, { passive: true })
    this.el.addEventListener("touchend", this.handleTouchEnd, { passive: true })
    document.addEventListener("keydown", this.handleKeydown)
  },

  updated() {
    // LiveView patches can rewrite the class attribute; keep the fullscreen
    // state while the user is inside the cell.
    if (this.expandedByPatch && !this.isExpanded()) this.expand()
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleCaptureClick, true)
    this.el.removeEventListener("click", this.handleClick)
    this.el.removeEventListener("pointerdown", this.handlePointerDown)
    this.el.removeEventListener("pointerup", this.handlePointerUp)
    this.el.removeEventListener("touchstart", this.handleTouchStart)
    this.el.removeEventListener("touchend", this.handleTouchEnd)
    document.removeEventListener("keydown", this.handleKeydown)
    if (this.el._cellFocus === this) delete this.el._cellFocus
    clearTimeout(this.closeTimer)
    clearTimeout(this.swipeTimer)
    this.releaseBody()
  },

  onCaptureClick(event) {
    // A swipe ends with a click; swallow it before the display opens editing.
    if (this.suppressClick) {
      this.suppressClick = false
      event.preventDefault()
      event.stopPropagation()
      return
    }

    if (!window.matchMedia(MOBILE_QUERY).matches) return
    if (this.isExpanded()) return

    // First tap: fullscreen only, do not let the display start editing.
    event.preventDefault()
    event.stopPropagation()
    this.expand()
  },

  onClick(event) {
    if (event.target.closest("[data-cell-exit]")) {
      event.preventDefault()
      event.stopPropagation()
      this.collapse()
      return
    }

    if (!window.matchMedia(MOBILE_QUERY).matches) return this.openField(event)
    if (this.isExpanded()) this.openField(event)
  },

  startSwipe(event) {
    this.startPoint = null
    if (!this.isExpanded()) return
    if (event.target.closest("textarea, input, select, button, a")) return

    const point = event.touches ? event.touches[0] : event
    if (!point) return

    this.startPoint = { x: point.clientX, y: point.clientY }
  },

  finishSwipe(event) {
    const start = this.startPoint
    this.startPoint = null
    if (!start || !this.isExpanded()) return

    const point = event.changedTouches ? event.changedTouches[0] : event
    if (!point) return

    const dx = point.clientX - start.x
    const dy = point.clientY - start.y
    if (Math.hypot(dx, dy) < SWIPE_THRESHOLD) return

    const horizontal = Math.abs(dx) > Math.abs(dy)

    // Any deliberate swipe ends with a click event; never treat it as a tap.
    this.suppressClick = true
    setTimeout(() => (this.suppressClick = false), 400)

    // Vertical swipes belong to scrolling when the cell content is taller than
    // the screen; horizontal swipes always navigate.
    if (!horizontal && this.el.scrollHeight > this.el.clientHeight + 4) return

    const delta = horizontal ? (dx < 0 ? 1 : -1) : dy < 0 ? 1 : -1
    // The cell slides away in the direction of the finger; the next one
    // arrives from the opposite edge.
    const direction = horizontal
      ? dx < 0
        ? { out: "left", in: "right" }
        : { out: "right", in: "left" }
      : dy < 0
        ? { out: "top", in: "bottom" }
        : { out: "bottom", in: "top" }

    this.navigate(horizontal ? "column" : "row", delta, direction)
  },

  // Move the fullscreen state to the cell `delta` steps away on one axis.
  navigate(axis, delta, direction) {
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

    this.collapse({ swipeOut: direction.out })
    target._cellFocus.expand({ swipeIn: direction.in })
  },

  isExpanded() {
    return this.el.classList.contains("is-expanded")
  },

  expand({ swipeIn = null } = {}) {
    document.querySelectorAll(".canvas-cell.is-expanded").forEach(cell => {
      if (cell === this.el) return
      // A cell that is sliding out keeps its frame until its animation ends.
      if ([...cell.classList].some(name => name.startsWith("is-swipe-out-"))) return
      cell.classList.remove("is-expanded", "is-closing")
    })

    this.el.classList.remove("is-closing", "is-settled")
    this.el.classList.add("is-expanded")

    if (swipeIn) {
      const swipeClass = `is-swipe-in-${swipeIn}`
      this.el.classList.add(swipeClass)

      // When the slide-in finishes, park the cell in a settled state: dropping
      // the class would otherwise re-trigger the fullscreen animation.
      const settle = event => {
        if (event && event.target !== this.el) return
        this.el.removeEventListener("animationend", settle)
        if (!this.el.classList.contains(swipeClass)) return
        this.el.classList.remove(swipeClass)
        this.el.classList.add("is-settled")
      }

      this.el.addEventListener("animationend", settle)
      clearTimeout(this.swipeTimer)
      this.swipeTimer = setTimeout(settle, 300)
    }

    this.expandedByPatch = true
    document.body.classList.add("overflow-hidden")
    this.el.scrollTop = 0
  },

  collapse({ instant = false, swipeOut = null } = {}) {
    if (!this.isExpanded()) return

    this.expandedByPatch = false

    if (instant) {
      this.finishCollapse()
    } else if (swipeOut) {
      // Slide out in the direction of the finger, then drop the fullscreen frame.
      this.el.classList.add(`is-swipe-out-${swipeOut}`)
      clearTimeout(this.closeTimer)
      this.closeTimer = setTimeout(() => {
        this.el.classList.remove(`is-swipe-out-${swipeOut}`)
        this.finishCollapse()
      }, 170)
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
    this.el.classList.remove("is-expanded", "is-settled")
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