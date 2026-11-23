// Canvas view tabs.
//
// The switch happens on the client: the panel is swapped the moment the tab
// is clicked and the server is told afterwards. Waiting for the server would
// put a network round trip — and a re-render of the whole grid — between the
// click and the new view, which reads as a lag on a phone.
//
// The server keeps the authority: it renders the panels, confirms the choice
// and owns the URL. This hook only makes that confirmation invisible.
//
// Split view (desktop) shows two panes: `primary` (L) on the left, `split` (R)
// on the right. The layout rules mirror `PscWeb.UnstrCanvasLive.Tabs.place/4`:
// a tab is in at most one pane, and moving a pane onto the tab the other pane
// shows swaps them.
//
// The header strip has one thumb per pane behind the tab that pane shows. A
// click on a tab moves the focused pane's thumb there (the phone's bottom bar
// always moves the left one); a thumb can also be dragged, by its tab or by its
// L/R tag, or moved with the arrow keys while its tab has focus. Thumbs and the
// divider between the panes are positioned through custom properties on <html>,
// which LiveView never patches, so a re-render does not reset them.
const PANEL_PREFIX = "canvas-panel-"
const SPLIT_KEY = "psc:canvas-split"
const SPLIT_MIN = 25
const SPLIT_MAX = 75
const DRAG_THRESHOLD = 4
const PANES = ["primary", "split"]

// A switch the server has not confirmed yet is dropped after this long, so a
// rejected switch does not pin the layout.
const PENDING_TIMEOUT = 3000

export default {
  mounted() {
    this.pending = null
    this.focus = this.el.dataset.focusPane || "primary"
    this.handleClick = event => this.onClick(event)
    this.handlePointerDown = event => this.onPointerDown(event)
    this.handleStripPointerDown = event => this.onStripPointerDown(event)
    this.handleKeydown = event => this.onKeydown(event)
    this.handleResize = () => this.positionThumbs()

    // Delegated: the tab buttons live in the header strip and in the bottom
    // app bar, not inside the panel this hook is attached to. Capture, so a
    // click that ends a drag can be stopped before LiveView sees it.
    document.addEventListener("click", this.handleClick, true)
    document.addEventListener("pointerdown", this.handleStripPointerDown)
    document.addEventListener("keydown", this.handleKeydown)
    this.el.addEventListener("pointerdown", this.handlePointerDown)
    window.addEventListener("resize", this.handleResize)

    // A patch that was already on its way when the tab was clicked can reset
    // the panel; keep the tab the user picked.
    this.observer = new MutationObserver(() => this.apply())
    this.observer.observe(this.el, {
      attributes: true,
      attributeFilter: ["class"],
      subtree: true,
    })

    // Tab names hide when the header is narrow, which moves every tab.
    this.resizeObserver = new ResizeObserver(this.handleResize)
    this.observeStrip()

    this.setSplit(this.storedSplit(), false)
    this.apply()
  },

  updated() {
    const server = this.serverState()
    if (this.pending && sameLayout(this.pending, server)) this.clearPending()
    if (!this.pending) this.focus = server.focus
    this.observeStrip()
    this.apply()
  },

  destroyed() {
    document.removeEventListener("click", this.handleClick, true)
    document.removeEventListener("pointerdown", this.handleStripPointerDown)
    document.removeEventListener("keydown", this.handleKeydown)
    window.removeEventListener("resize", this.handleResize)
    this.observer?.disconnect()
    this.resizeObserver?.disconnect()
    this.observer = null
    clearTimeout(this.pendingTimer)
    delete document.documentElement.dataset.canvasThumbs
  },

  strip() {
    return document.getElementById("canvas-tabs")
  },

  observeStrip() {
    const strip = this.strip()
    if (!strip || strip === this.observedStrip) return

    this.resizeObserver.disconnect()
    this.resizeObserver.observe(strip)
    this.observedStrip = strip
  },

  serverState() {
    const data = this.el.dataset
    return {
      primary: data.activeTab,
      split: data.splitTab || null,
      focus: data.splitTab ? data.focusPane || "primary" : "primary",
    }
  },

  state() {
    return this.pending || {...this.serverState(), focus: this.focus}
  },

  clearPending() {
    this.pending = null
    clearTimeout(this.pendingTimer)
  },

  paneOf(tab) {
    const {primary, split} = this.state()
    return tab === primary ? "primary" : split && tab === split ? "split" : null
  },

  // Applies a switch at once; `push` also tells the server (a click already
  // does that through its own phx-click).
  move(pane, tab, push) {
    const current = this.state()
    if (!current.split) pane = "primary"
    if (current[pane] === tab) {
      this.positionThumbs()
      return
    }

    this.pending = {...place(current, pane, tab), focus: pane}
    this.focus = pane
    clearTimeout(this.pendingTimer)
    this.pendingTimer = setTimeout(() => {
      this.pending = null
      this.apply()
    }, PENDING_TIMEOUT)

    if (push) this.pushEvent("select_tab", {tab, pane})
    this.apply()
  },

  onClick(event) {
    if (this.suppressClick) {
      this.suppressClick = false
      event.preventDefault()
      event.stopPropagation()
      return
    }

    const button = event.target.closest('[role="tab"][data-tab]')
    if (!button) return

    const current = this.state()
    const pane = current.split ? button.dataset.pane || this.focus : "primary"
    this.move(pane, button.getAttribute("data-tab"), false)
  },

  // A press anywhere in a pane makes it the one the header strip targets.
  onPointerDown(event) {
    const divider = event.target.closest("#canvas-split-divider")
    if (divider) return this.startDividerDrag(event, divider)

    const pane = event.target.closest("[data-pane]")?.dataset.pane
    if (!pane || !this.state().split || pane === this.focus) return

    this.setFocus(pane)
  },

  setFocus(pane) {
    this.focus = pane
    if (this.pending) this.pending.focus = pane
    this.pushEvent("focus_pane", {pane})
    this.apply()
  },

  // Dragging a thumb: press on its tag, or on the tab a pane shows, and move.
  // Until the pointer travels a few pixels it is an ordinary click.
  onStripPointerDown(event) {
    const strip = this.strip()
    if (event.button !== 0 || !strip?.contains(event.target)) return

    const tag = event.target.closest(".canvas-tab-thumb-tag")
    const button = event.target.closest('[role="tab"][data-tab]')
    const pane = tag
      ? tag.closest(".canvas-tab-thumb").dataset.pane
      : button && this.paneOf(button.getAttribute("data-tab"))
    if (!pane) return

    const thumb = document.getElementById(`canvas-tab-thumb-${pane}`)
    const origin = this.thumbBox(pane)
    if (!thumb || !origin) return
    if (tag) event.preventDefault()

    const startX = event.clientX
    let dragging = false

    const move = moveEvent => {
      const dx = moveEvent.clientX - startX
      if (!dragging) {
        if (Math.abs(dx) < DRAG_THRESHOLD) return
        dragging = true
        capture(strip, event.pointerId)
        thumb.setAttribute("data-dragging", "")
        if (this.state().split && pane !== this.focus) this.setFocus(pane)
      }

      const max = strip.clientWidth - origin.width
      const x = Math.min(max, Math.max(0, origin.x + dx))
      document.documentElement.style.setProperty(`--canvas-thumb-${pane}-x`, `${x}px`)
    }

    const up = () => {
      strip.removeEventListener("pointermove", move)
      strip.removeEventListener("pointerup", up)
      strip.removeEventListener("pointercancel", up)
      if (!dragging) return

      thumb.removeAttribute("data-dragging")
      // The pointer is released over a tab or between two; either way a click
      // may follow, and it must not switch the focused pane as well.
      this.suppressClick = true
      setTimeout(() => (this.suppressClick = false), 0)

      const tab = this.nearestTab(thumb)
      if (tab) this.move(pane, tab, true)
      else this.positionThumbs()
    }

    strip.addEventListener("pointermove", move)
    strip.addEventListener("pointerup", up)
    strip.addEventListener("pointercancel", up)
  },

  nearestTab(thumb) {
    const box = thumb.getBoundingClientRect()
    const center = box.left + box.width / 2
    let best = null

    for (const button of this.strip().querySelectorAll('[role="tab"][data-tab]')) {
      const rect = button.getBoundingClientRect()
      const distance = Math.abs(rect.left + rect.width / 2 - center)
      if (!best || distance < best.distance) best = {tab: button.dataset.tab, distance}
    }

    return best?.tab
  },

  onKeydown(event) {
    if (event.target.id === "canvas-split-divider") return this.onDividerKey(event)

    const step = {ArrowLeft: -1, ArrowRight: 1}[event.key]
    const button = event.target.closest?.('#canvas-tabs [role="tab"][data-tab]')
    if (!step || !button) return

    event.preventDefault()
    const buttons = [...this.strip().querySelectorAll('[role="tab"][data-tab]')]
    const next = buttons[buttons.indexOf(button) + step]
    if (!next) return

    // On a tab a pane shows, the arrows carry that pane along; elsewhere they
    // only move the keyboard focus.
    const pane = this.paneOf(button.dataset.tab)
    if (pane) this.move(pane, next.dataset.tab, true)
    next.focus()
  },

  onDividerKey(event) {
    const step = {ArrowLeft: -5, ArrowRight: 5}[event.key]
    if (!step) return

    event.preventDefault()
    this.setSplit(this.split + step, true)
  },

  startDividerDrag(event, divider) {
    event.preventDefault()
    capture(divider, event.pointerId)
    divider.setAttribute("data-dragging", "")

    const move = moveEvent => {
      const rect = this.el.getBoundingClientRect()
      this.setSplit(((moveEvent.clientX - rect.left) / rect.width) * 100, false)
    }

    const up = () => {
      divider.removeAttribute("data-dragging")
      divider.removeEventListener("pointermove", move)
      divider.removeEventListener("pointerup", up)
      divider.removeEventListener("pointercancel", up)
      this.setSplit(this.split, true)
    }

    divider.addEventListener("pointermove", move)
    divider.addEventListener("pointerup", up)
    divider.addEventListener("pointercancel", up)
  },

  storedSplit() {
    try {
      const value = Number(localStorage.getItem(SPLIT_KEY))
      return value > 0 ? value : 50
    } catch {
      return 50
    }
  },

  setSplit(value, persist) {
    this.split = Math.round(Math.min(SPLIT_MAX, Math.max(SPLIT_MIN, value)))
    document.documentElement.style.setProperty("--canvas-split", `${this.split}%`)
    document
      .getElementById("canvas-split-divider")
      ?.setAttribute("aria-valuenow", String(this.split))

    if (persist) {
      try {
        localStorage.setItem(SPLIT_KEY, String(this.split))
      } catch {
        // Storage may be unavailable (private mode); the position still applies.
      }
    }
  },

  // Where a pane's tab sits in the strip: the thumb's target.
  thumbBox(pane) {
    const tab = this.state()[pane]
    const button = tab && document.getElementById(`canvas-tab-${tab}`)
    if (!button || !button.offsetParent) return null
    return {x: button.offsetLeft, width: button.offsetWidth}
  },

  positionThumbs() {
    const root = document.documentElement
    let placed = false

    for (const pane of PANES) {
      const box = this.thumbBox(pane)
      if (!box) continue
      root.style.setProperty(`--canvas-thumb-${pane}-x`, `${box.x}px`)
      root.style.setProperty(`--canvas-thumb-${pane}-w`, `${box.width}px`)
      placed = true
    }

    // Until a thumb has a place, the selected tab keeps its own highlight.
    if (placed) root.dataset.canvasThumbs = ""
  },

  apply() {
    const {primary, split, focus} = this.state()
    const paneOf = tab => (tab === primary ? "primary" : split && tab === split ? "split" : null)

    this.el.dataset.focusPane = focus

    for (const panel of document.querySelectorAll(`[id^="${PANEL_PREFIX}"]`)) {
      const pane = paneOf(panel.id.slice(PANEL_PREFIX.length))
      panel.classList.toggle("hidden", !pane)
      if (pane) {
        if (panel.dataset.pane !== pane) panel.dataset.pane = pane
      } else if (panel.hasAttribute("data-pane")) {
        panel.removeAttribute("data-pane")
      }
    }

    for (const button of document.querySelectorAll('[role="tab"][data-tab]')) {
      const tab = button.getAttribute("data-tab")

      if (button.dataset.pane) {
        // The bottom bar, which shows the left pane.
        button.setAttribute("aria-selected", String(tab === primary))
      } else {
        // The header strip: the focused pane's tab, plus the pane of each open tab.
        button.setAttribute("aria-selected", String(tab === (focus === "split" && split ? split : primary)))
        const badge = split ? {primary: "L", split: "R"}[paneOf(tab)] : null
        if (badge) button.dataset.paneBadge = badge
        else button.removeAttribute("data-pane-badge")
      }
    }

    this.positionThumbs()
  },
}

function place({primary, split}, pane, tab) {
  if (!split) return {primary: tab, split: null}
  if (pane === "split") return tab === primary ? {primary: split, split: tab} : {primary, split: tab}
  return tab === split ? {primary: tab, split: primary} : {primary: tab, split}
}

// Keeps a drag going when the pointer leaves the element. It throws for a
// pointer that is no longer active, which only costs that guarantee.
function capture(el, pointerId) {
  try {
    el.setPointerCapture(pointerId)
  } catch {
    // Released already; the listeners still see moves over the element.
  }
}

function sameLayout(a, b) {
  return a.primary === b.primary && (a.split || null) === (b.split || null)
}
