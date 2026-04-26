export default {
  mounted() {
    this.cellKey = this.el.dataset.cellKey
    this.field = this.el.dataset.field
    this.currentUserId = Number(this.el.dataset.currentUserId)

    this.input = this.el.querySelector('textarea, input')
    this.display = this.el.querySelector('.md-render')

    const initialValue = this.input ? this.input.value : ''

    // Request server-side render for initial value
    this.pushEvent('render_field', { cell_key: this.cellKey, field: this.field, value: initialValue })

    // Receive rendered html from server
    this.handleEvent('field_rendered', payload => {
      if (String(payload.cell_key) !== String(this.cellKey) || String(payload.field) !== String(this.field)) return
      const html = payload.html || ''
      if (!html || html.trim() === '') {
        this.display.innerHTML = '<div class="p-2 rounded text-gray-400 dark:text-gray-400">Click to edit</div>'
        this.display.classList.add('empty')
      } else {
        this.display.innerHTML = html
        this.display.classList.remove('empty')
      }
    })

    // Sync updates from other users
    this.handleEvent('cell_updated', ({ cell_key, field, new_value, from_user_id }) => {
      if (String(cell_key) !== String(this.cellKey) || String(field) !== String(this.field)) return

      const isServerResync = from_user_id === -1
      if (!isServerResync && Number(from_user_id) === this.currentUserId && document.activeElement === this.input) {
        return
      }

      const cursorPos = this.input && this.input.selectionStart ? this.input.selectionStart : 0
      if (this.input) this.input.value = new_value || ''

      if (document.activeElement !== this.input) {
        this.pushEvent('render_field', { cell_key: this.cellKey, field: this.field, value: new_value })
      }

      if (this.input && this.input.setSelectionRange) {
        const pos = Math.min(cursorPos, (this.input.value || '').length)
        this.input.setSelectionRange(pos, pos)
      }
    })

    // Click rendered view to edit
    this.display.addEventListener('click', _ => {
      this.display.classList.add('hidden')
      if (this.input) {
        this.input.classList.remove('hidden')
        this.input.focus()
      }
    })

    // Debounced updates while typing (longer to avoid premature render)
    let debounceTimer = null
    const DEBOUNCE_MS = 500

    if (this.input) {
      this.input.addEventListener('input', e => {
        const val = e.target.value
        if (debounceTimer) clearTimeout(debounceTimer)
        debounceTimer = setTimeout(() => {
          this.pushEvent('update_cell', { cell_key: this.cellKey, field: this.field, value: val })
        }, DEBOUNCE_MS)
      })

      // On blur, send final update and request render
      this.input.addEventListener('blur', e => {
        const val = e.target.value
        if (debounceTimer) { clearTimeout(debounceTimer); debounceTimer = null }
        this.pushEvent('update_cell', { cell_key: this.cellKey, field: this.field, value: val })
        this.pushEvent('render_field', { cell_key: this.cellKey, field: this.field, value: val })
        this.input.classList.add('hidden')
        this.display.classList.remove('hidden')
      })
    }
  }
}
