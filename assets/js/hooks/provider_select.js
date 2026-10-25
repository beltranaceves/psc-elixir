// The provider list is server-driven (`phx-click`), so Escape has to be
// intercepted before SaladUI's dialog sees it: otherwise the dialog closes
// instead of the list. Capture runs from the wrapper down to the focused
// trigger, ahead of the dialog's own keydown handling.
export default {
  mounted() {
    this.onKeydown = (event) => {
      if (event.key !== "Escape") return;
      if (!this.el.querySelector("#connection-provider-list")) return;

      event.preventDefault();
      event.stopPropagation();
      this.pushEvent("close_provider_list", {});
    };

    this.el.addEventListener("keydown", this.onKeydown, true);
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.onKeydown, true);
  }
};
