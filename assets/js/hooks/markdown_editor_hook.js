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
    this.mode = this.el.querySelector('[data-editor-mode]')
    this.hint = this.el.querySelector('[data-editor-hint]')
    this.currentUserId = this.input?.dataset.currentUserId
    this.pendingPreviewContent = null

    this.renderEvent = this.el.dataset.renderEvent || 'document_rendered'
    this.updateEvent = this.el.dataset.updateEvent || 'content_updated'
    this.previewEvent = this.el.dataset.previewEvent || 'render_document'

    if (!this.input || !this.form || !this.preview || !this.previewContent) return

    const initialValue = this.input.getAttribute('value')
    if (initialValue !== null) this.input.value = initialValue

    this.input.addEventListener('focus', () => this.showEditor())
    this.input.addEventListener('blur', () => this.requestPreview())
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
    this.pushEvent(this.previewEvent, { content })
  },

  showEditor() {
    this.form.classList.remove('hidden')
    this.preview.classList.add('hidden')
    this.mode.textContent = 'Editing Markdown'
    this.hint.textContent = 'Click outside to preview'
    this.preview.setAttribute('aria-hidden', 'true')
  },

  showPreview() {
    this.form.classList.add('hidden')
    this.preview.classList.remove('hidden')
    this.mode.textContent = 'Markdown preview'
    this.hint.textContent = 'Click to edit'
    this.preview.removeAttribute('aria-hidden')
  },
}
