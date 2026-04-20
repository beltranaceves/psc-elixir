export default {
  mounted() {
    this.currentUserId = Number(this.el.dataset.currentUserId)
    this.cellKey = this.el.dataset.cellKey
    this.field = this.el.dataset.field

    // Initialize value from attribute if present
    const initialValue = this.el.getAttribute('value')
    if (initialValue !== null) {
      this.el.value = initialValue
    }

    this.handleEvent('cell_updated', ({ cell_key, field, new_value, from_user_id }) => {
      // Only act on updates that target this input (coerce to string for robust matching)
      if (String(cell_key) !== this.cellKey || String(field) !== this.field) return

      const isServerResync = from_user_id === -1
      // If the change came from the same user and the input is focused, skip to avoid clobbering
      if (!isServerResync && Number(from_user_id) === this.currentUserId && document.activeElement === this.el) {
        return
      }

      const cursorPos = this.el.selectionStart
      this.el.value = new_value
      if (cursorPos <= new_value.length) {
        this.el.setSelectionRange(cursorPos, cursorPos)
      }
    })

    // debounce input pushes to avoid flooding the server
    let debounceTimer = null
    const DEBOUNCE_MS = 200

    this.el.addEventListener('input', e => {
      const val = e.target.value
      if (debounceTimer) clearTimeout(debounceTimer)
      debounceTimer = setTimeout(() => {
        this.pushEvent('update_cell', {
          cell_key: this.cellKey,
          field: this.field,
          value: val
        })
      }, DEBOUNCE_MS)
    })
  }
}
