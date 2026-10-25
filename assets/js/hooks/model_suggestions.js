// Inline model suggestions for the connection dialog.
//
// The native <datalist> popup is positioned in the page's untransformed
// coordinate space, which puts it in the wrong place inside the dialog, whose
// panel is centred with `translate` (a Chromium bug). This renders the same
// suggestions as a normal absolutely-positioned list under the input instead.
const ACTIVE_ATTR = "data-active";

export default {
  mounted() {
    this.input = this.el.querySelector("input");
    this.list = this.el.querySelector("[data-suggestions]");
    this.empty = this.el.querySelector("[data-suggestions-empty]");

    this.input.setAttribute("role", "combobox");
    this.input.setAttribute("aria-autocomplete", "list");
    this.input.setAttribute("aria-controls", this.list.id);
    this.input.setAttribute("aria-expanded", "false");

    this.onInput = () => this.filterAndShow();
    this.onFocus = () => this.show();
    this.onKeydown = (event) => this.handleKeydown(event);
    this.onFocusOut = (event) => {
      if (!this.el.contains(event.relatedTarget)) this.hide();
    };
    this.onPointerDown = (event) => {
      if (!this.el.contains(event.target)) this.hide();
    };

    this.input.addEventListener("input", this.onInput);
    this.input.addEventListener("focus", this.onFocus);
    this.input.addEventListener("keydown", this.onKeydown);
    this.el.addEventListener("focusout", this.onFocusOut);
    document.addEventListener("pointerdown", this.onPointerDown, true);

    // Keep focus in the input while the list is clicked.
    this.list.addEventListener("mousedown", (event) => event.preventDefault());
    this.list.addEventListener("click", (event) => {
      const option = event.target.closest("[data-suggestion]");
      if (option) this.pick(option.dataset.suggestion);
    });

    this.refresh();
  },

  updated() {
    this.refresh();
  },

  destroyed() {
    document.removeEventListener("pointerdown", this.onPointerDown, true);
  },

  refresh() {
    this.list = this.el.querySelector("[data-suggestions]");
    this.empty = this.el.querySelector("[data-suggestions-empty]");
    this.count = this.el.querySelector("[data-suggestions-count]");
    this.options = Array.from(this.list.querySelectorAll("[data-suggestion]"));
    this.active = -1;

    // The server renders the list hidden; a LiveView patch (test result, form
    // errors, a provider change) should leave it closed.
    this.filter();
    this.hide();
  },

  filterAndShow() {
    this.filter();
    this.show();
  },

  filter() {
    const query = this.input.value.trim().toLowerCase();
    let matches = 0;

    for (const option of this.options) {
      const match =
        query === "" || option.dataset.suggestion.toLowerCase().includes(query);
      option.hidden = !match;
      option.setAttribute(ACTIVE_ATTR, "false");
      if (match) matches += 1;
    }

    this.active = -1;
    this.empty.hidden = matches > 0;
    if (this.count) this.count.textContent = String(matches);
    this.input.setAttribute("aria-expanded", String(matches > 0 && !this.list.hidden));
  },

  show() {
    if (!this.list || this.options.length === 0) return;
    this.filter();
    this.list.hidden = false;
    this.input.setAttribute("aria-expanded", "true");
  },

  hide() {
    if (!this.list) return;
    this.list.hidden = true;
    this.input.setAttribute("aria-expanded", "false");
    this.active = -1;
  },

  handleKeydown(event) {
    if (event.key === "Escape") {
      if (!this.list.hidden) {
        event.stopPropagation();
        this.hide();
      }
      return;
    }

    if (event.key === "Tab") {
      this.hide();
      return;
    }

    if (event.key !== "ArrowDown" && event.key !== "ArrowUp" && event.key !== "Enter") {
      return;
    }

    if (this.list.hidden) this.show();

    const visible = this.options.filter((option) => !option.hidden);

    if (event.key === "Enter") {
      if (!this.list.hidden) {
        // An open suggestion list means Enter belongs to the combobox, not the
        // form: without this, an unmatched query would submit the dialog.
        event.preventDefault();

        if (this.active >= 0 && visible[this.active]) {
          this.pick(visible[this.active].dataset.suggestion);
        }
      }
      return;
    }

    event.preventDefault();
    if (visible.length === 0) return;

    const delta = event.key === "ArrowDown" ? 1 : -1;
    this.active = (this.active + delta + visible.length) % visible.length;

    visible.forEach((option, index) => {
      option.setAttribute(ACTIVE_ATTR, String(index === this.active));
    });

    visible[this.active].scrollIntoView({block: "nearest"});
  },

  pick(value) {
    this.input.value = value;
    this.input.dispatchEvent(new Event("input", {bubbles: true}));
    this.hide();
    this.input.focus();
  }
};
