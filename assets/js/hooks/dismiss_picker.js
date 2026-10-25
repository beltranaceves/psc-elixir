// Close an open colour picker when the user clicks outside it.
//
// The pickers are server state (a LiveView assign), so hiding them in the
// client would be undone by the next patch. This hook watches document clicks
// while a picker is open and asks the server to clear it. Clicks on the
// trigger or inside the panel carry `data-color-picker`, so they are left to
// the LiveView: the trigger still toggles, and the swatches still apply.
const PICKER_SELECTOR = "[data-color-picker]"

export default {
  mounted() {
    this.onDocumentClick = event => {
      if (!this.pickerOpen()) return
      if (event.target.closest(PICKER_SELECTOR)) return

      this.pushEvent("dismiss_color_pickers", {})
    }

    this.onKeydown = event => {
      if (event.key !== "Escape" || !this.pickerOpen()) return

      this.pushEvent("dismiss_color_pickers", {})
    }

    document.addEventListener("click", this.onDocumentClick, true)
    document.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    document.removeEventListener("click", this.onDocumentClick, true)
    document.removeEventListener("keydown", this.onKeydown)
  },

  pickerOpen() {
    return this.el.dataset.pickerOpen === "true"
  },
}
