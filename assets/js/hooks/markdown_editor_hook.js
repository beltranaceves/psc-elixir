// The reusable Markdown editor.
//
// The parts are found through data attributes, not hardcoded ids, so more
// than one editor can live on the same page — a note inside the canvas
// editor, for instance, next to a canvas cell.
//
// The server events it listens to are configurable, because they belong to
// the LiveView that owns the editor:
//
//   <render event> — { content, html }         the server re-rendered the Markdown
//   <update event> — { content, from_user_id }  a remote edit
//   <preview event> — { content }               the client asks for a re-render
//
// `from_user_id` of -1 means the server is resynchronising a diverged client.

// The length of the longest shared start of the two strings.
function commonPrefixLength(current, incoming) {
  const max = Math.min(current.length, incoming.length)
  let length = 0
  while (length < max && current[length] === incoming[length]) length++
  return length
}

// The length of the longest shared end, without overlapping the prefix: the
// two sides of the patch have to stay disjoint.
function commonSuffixLength(current, incoming, prefix) {
  const max = Math.min(current.length, incoming.length) - prefix
  let length = 0

  while (
    length < max &&
    current[current.length - 1 - length] === incoming[incoming.length - 1 - length]
  ) {
    length++
  }

  return length
}

// Where a caret position in the old text lands in the patched text: before
// the patch it stays put, after it moves by the patch's length change, and
// inside it lands at the end of what was inserted.
function remapPosition(position, patchStart, patchEnd, insertedLength) {
  if (position <= patchStart) return position
  if (position >= patchEnd) return position + insertedLength - (patchEnd - patchStart)
  return patchStart + insertedLength
}

export default {
  mounted() {
    this.form = this.el.querySelector('[data-editor-form]')
    this.input = this.el.querySelector('[data-editor-input]')
    this.preview = this.el.querySelector('[data-editor-preview]')
    this.previewContent = this.el.querySelector('[data-editor-content]')
    this.currentUserId = Number(this.input?.dataset.currentUserId)
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

    this.handleEvent(this.updateEvent, ({ content, from_user_id }) => {
      const isServerResync = from_user_id === -1

      // Our own edit echoed back while we type: the textarea already has it.
      if (
        !isServerResync &&
        Number(from_user_id) === this.currentUserId &&
        document.activeElement === this.input
      ) {
        return
      }

      this.applyRemoteContent(content || '')
      this.resize()
    })

    this.showPreview()
  },

  // Apply a remote edit as the smallest replacement we can, instead of
  // overwriting the textarea. Replacing the whole value threw the local caret
  // to the end on every keystroke from the other user, so two people could
  // not type in the same note. Patching the one run that changed leaves the
  // text around it alone, and the caret is remapped so it stays where the
  // local user left it.
  applyRemoteContent(content) {
    const current = this.input.value
    if (content === current) return

    const start = this.input.selectionStart
    const end = this.input.selectionEnd

    const prefix = commonPrefixLength(current, content)
    const suffix = commonSuffixLength(current, content, prefix)
    const currentEnd = current.length - suffix
    const inserted = content.slice(prefix, content.length - suffix)

    this.input.setRangeText(inserted, prefix, currentEnd, 'preserve')

    if (start !== null && end !== null) {
      this.input.setSelectionRange(
        remapPosition(start, prefix, currentEnd, inserted.length),
        remapPosition(end, prefix, currentEnd, inserted.length),
      )
    }
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
