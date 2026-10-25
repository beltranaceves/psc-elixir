// Chat behaviour for the canvas agent panel: the transcript follows new
// messages while the reader stays near the bottom, and the composer behaves
// like a chat box (Enter sends, Shift+Enter inserts a line, and it grows with
// its content instead of showing the native resize grip).

const NEAR_BOTTOM_PX = 96
const COMPOSER_MAX_HEIGHT_PX = 192

export default {
  mounted() {
    this.pinned = true
    this.composer = null
    this.boundForm = null

    // Scroll events do not bubble, so listen in the capture phase and read the
    // transcript from the current DOM: LiveView replaces it on a chat switch.
    this.el.addEventListener(
      "scroll",
      (event) => {
        if (event.target.id !== "canvas-agent-messages") return
        const {scrollTop, scrollHeight, clientHeight} = event.target
        this.pinned = scrollHeight - scrollTop - clientHeight < NEAR_BOTTOM_PX
      },
      {capture: true, passive: true}
    )

    // The panel outlives its session: the composer only appears once a chat
    // starts, and parts of the tree can be replaced after a reconnect.
    this.observer = new MutationObserver((mutations) => {
      if (this.addedMessage(mutations)) this.pinned = true
      this.bindComposer()
      if (this.pinned) this.scrollToLatest()
    })
    this.observer.observe(this.el, {childList: true, subtree: true, characterData: true})

    this.bindComposer()
    this.scrollToLatest()
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
  },

  addedMessage(mutations) {
    return mutations.some((mutation) =>
      [...mutation.addedNodes].some(
        (node) => node.nodeType === 1 && node.id?.startsWith("agent-message-")
      )
    )
  },

  bindComposer() {
    const textarea = this.el.querySelector("#canvas-agent-composer textarea")
    if (!textarea) return

    if (textarea !== this.composer) {
      this.composer = textarea

      textarea.addEventListener("keydown", (event) => {
        if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
        if (textarea.disabled || !this.boundForm) return
        event.preventDefault()
        if (textarea.value.trim() !== "") this.boundForm.requestSubmit()
      })

      textarea.addEventListener("input", () => this.resizeComposer())
    }

    const form = textarea.closest("form")

    if (form && form !== this.boundForm) {
      this.boundForm = form

      form.addEventListener("submit", () => {
        // LiveView reads the form synchronously; the next frame should start
        // from an empty, single-line composer.
        requestAnimationFrame(() => {
          if (!this.composer) return
          this.composer.value = ""
          this.resizeComposer()
        })
      })
    }

    this.resizeComposer()
  },

  resizeComposer() {
    if (!this.composer) return
    this.composer.style.height = "auto"
    this.composer.style.height = `${Math.min(this.composer.scrollHeight, COMPOSER_MAX_HEIGHT_PX)}px`
  },

  scrollToLatest() {
    const transcript = this.el.querySelector("#canvas-agent-messages")
    if (!transcript) return

    requestAnimationFrame(() => {
      transcript.scrollTop = transcript.scrollHeight
    })
  }
}
