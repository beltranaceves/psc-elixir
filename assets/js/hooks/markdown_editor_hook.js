// The reusable Markdown editor.
//
// The parts are found through data attributes, not hardcoded ids, so more
// than one editor can live on the same page — a note inside the canvas
// editor, for instance, next to a canvas cell.
//
// The two server events it listens to are configurable, because they belong
// to the LiveView that owns the editor:
//
//   <render event> — { content, html }   the server re-rendered the Markdown
//   <update event> — { newContent, fromUserId }  a remote edit
//   <preview event> — { content }         the client asks for a re-render
//
// `fromUserId` of -1 means the server is resynchronising a diverged client.
export default {
  mounted() {
    this.form = this.el.querySelector('[data-editor-form]')
    this.input = this.el.querySelector('[data-editor-input]')
    this.preview = this.el.querySelector('[data-editor-preview]')
    this.previewContent = this.el.querySelector('[data-editor-content]')
    this.currentUserId = this.input?.dataset.currentUserId
    this.pendingPreviewContent = null

    this.renderEvent = this.el.dataset.renderEvent || 'document_rendered'
    this.updateEvent = this.el.dataset.updateEvent || 'content_updated'
    this.previewEvent = this.el.dataset.previewEvent || 'render_document'
    this.autoGrow = this.el.dataset.autoGrow === 'true'

    if (!this.input || !this.form || !this.preview || !this.previewContent) return

    const initialValue = this.input.getAttribute('value')
    if (initialValue !== null) this.input.value = initialValue

    this.input.addEventListener('focus', () => this.showEditor())
    this.input.addEventListener('blur', () => this.requestPreview())
    this.input.addEventListener('input', () => this.resize())
    this.preview.addEventListener('click', () => this.edit())
    this.preview.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault()
        this.edit()
      }
    })

    this.handleEvent(this.renderEvent, ({ content, html }) => {
      if (content !== this.input.value) return

      this.previewContent.innerHTML = html || ''

      if (this.pendingPreviewContent === content || document.activeElement !== this.input) {
        this.pendingPreviewContent = null
        this.showPreview()
      }
    })

    this.handleEvent(this.updateEvent, ({ newContent, fromUserId }) => {
      const isServerResync = fromUserId == -1

      if (
        !isServerResync &&
        this.currentUserId == fromUserId &&
        document.activeElement === this.input
      ) {
        return
      }

      const cursorPos = this.input.selectionStart || 0
      this.input.value = newContent || ''

      if (cursorPos <= this.input.value.length) {
        this.input.setSelectionRange(cursorPos, cursorPos)
      }

      this.resize()
    })

    this.showPreview()
  },

  edit() {
    this.showEditor()
    this.input.focus()
  },

  requestPreview() {
    const content = this.input.value
    this.pendingPreviewContent = content

    // The change event carries the form's hidden fields, so the preview
    // request carries them too — the server needs the same context to know
    // which editor is asking.
    const payload = { content }

    this.form.querySelectorAll('input[type="hidden"]').forEach((el) => {
      if (el.name) payload[el.name] = el.value
    })

    this.pushEvent(this.previewEvent, payload)
  },

  // An auto-growing editor sizes itself to its text, so the card around it
  // grows instead of scrolling. A hidden element reports no height, so this
  // only runs while the textarea is on screen.
  resize() {
    if (!this.autoGrow) return

    this.input.style.height = 'auto'
    this.input.style.height = `${this.input.scrollHeight}px`
  },

  showEditor() {
    this.form.classList.remove('hidden')
    this.preview.classList.add('hidden')
    this.preview.setAttribute('aria-hidden', 'true')
    this.resize()
  },

  showPreview() {
    this.form.classList.add('hidden')
    this.preview.classList.remove('hidden')
    this.preview.removeAttribute('aria-hidden')
  },
}
