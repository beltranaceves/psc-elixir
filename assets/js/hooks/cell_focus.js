// Clicking anywhere in a canvas cell opens the nearest markdown field for
// editing, so users do not have to hit the text itself. Clicks that already
// land on a field (or a control) keep their own behaviour.
export default {
  mounted() {
    this.el.addEventListener('click', e => {
      if (e.target.closest('textarea, input, select, button, a')) return

      const openField = wrapper => {
        const display = wrapper && wrapper.querySelector('.md-render')
        // A hidden display means the field is already open for editing.
        if (display && !display.classList.contains('hidden')) display.click()
      }

      const inside = e.target.closest('[data-field-wrapper]')
      if (inside) return openField(inside)

      const wrappers = [...this.el.querySelectorAll('[data-field-wrapper]')]
      if (wrappers.length === 0) return

      const nearest = wrappers.reduce((best, wrapper) => {
        const rect = wrapper.getBoundingClientRect()
        const distance = Math.abs((rect.top + rect.bottom) / 2 - e.clientY)
        return !best || distance < best.distance ? { wrapper, distance } : best
      }, null)

      openField(nearest.wrapper)
    })
  },
}
