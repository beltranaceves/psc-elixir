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
      // Only act on updates that target this input
      if (cell_key !== this.cellKey || field !== this.field) return

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
  }
}
