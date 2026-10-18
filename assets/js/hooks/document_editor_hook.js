export default {
  mounted() {
    this.input = this.el.querySelector('#editor')
    this.form = this.el.querySelector('#editor-form')
    this.preview = this.el.querySelector('#document-markdown-preview')
    this.previewContent = this.preview?.querySelector('.markdown-preview')
    this.mode = this.el.querySelector('[data-editor-mode]')
    this.hint = this.el.querySelector('[data-editor-hint]')
    this.currentUserId = this.input?.dataset.currentUserId
    this.pendingPreviewContent = null

    if (!this.input || !this.form || !this.preview || !this.previewContent) return

    const initialValue = this.input.getAttribute('value')
    if (initialValue !== null) this.input.value = initialValue

    this.input.addEventListener('focus', () => this.showEditor())
    this.input.addEventListener('blur', () => this.requestPreview())
    this.preview.addEventListener('click', () => this.edit())
    this.preview.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault()
        this.edit()
      }
    })

    this.handleEvent('document_rendered', ({ content, html }) => {
      if (content !== this.input.value) return

      this.previewContent.innerHTML = html || ''

      if (this.pendingPreviewContent === content || document.activeElement !== this.input) {
        this.pendingPreviewContent = null
        this.showPreview()
      }
    })

    this.handleEvent('content_updated', ({ newContent, fromUserId }) => {
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
    this.pushEvent('render_document', { content })
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
  }
}
