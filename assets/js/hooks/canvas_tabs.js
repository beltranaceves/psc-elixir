// Canvas view tabs.
//
// The switch happens on the client: the panel is swapped the moment the tab
// is clicked and the server is told afterwards. Waiting for the server would
// put a network round trip — and a re-render of the whole grid — between the
// click and the new view, which reads as a lag on a phone.
//
// The server keeps the authority: it renders the panels, confirms the choice
// and owns the URL. This hook only makes that confirmation invisible.
const PANEL_PREFIX = "canvas-panel-"

export default {
  mounted() {
    this.currentTab = this.el.getAttribute("data-active-tab")
    this.handleClick = event => this.onClick(event)

    // Delegated: the tab buttons live in the header strip and in the bottom
    // app bar, not inside the panel this hook is attached to.
    document.addEventListener("click", this.handleClick, true)

    // A patch that was already on its way when the tab was clicked can reset
    // the panel; keep the tab the user picked.
    this.observer = new MutationObserver(() => {
      if (this.currentTab) this.show(this.currentTab)
    })
    this.observer.observe(this.el, {
      attributes: true,
      attributeFilter: ["class"],
      subtree: true,
    })
  },

  updated() {
    if (this.currentTab) this.show(this.currentTab)
  },

  destroyed() {
    document.removeEventListener("click", this.handleClick, true)
    this.observer?.disconnect()
    this.observer = null
  },

  onClick(event) {
    const button = event.target.closest('[role="tab"][data-tab]')
    if (!button) return

    const tab = button.getAttribute("data-tab")
    if (!tab || tab === this.currentTab) return

    this.show(tab)
  },

  show(tab) {
    this.currentTab = tab

    for (const panel of document.querySelectorAll(`[id^="${PANEL_PREFIX}"]`)) {
      panel.classList.toggle("hidden", panel.id !== `${PANEL_PREFIX}${tab}`)
    }

    for (const button of document.querySelectorAll('[role="tab"][data-tab]')) {
      button.setAttribute(
        "aria-selected",
        String(button.getAttribute("data-tab") === tab),
      )
    }
  },
}
