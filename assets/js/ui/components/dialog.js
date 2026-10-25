// saladui/components/dialog.js
import Component from "../core/component.js";
import SaladUI from "../index.js";
import FocusTrap from "../core/focus-trap.js";
import ClickOutsideMonitor from "../core/click-outside.js";

class DialogComponent extends Component {
  constructor(el, hookContext) {
    super(el, {
      hookContext,
      initialState: "closed",
    });

    // Initialize properties
    this.root = this.el;
    this.content = this.getPart("content");
    this.contentPanel = this.getPart("content-panel");
    this.config.preventDefaultKeys = ["Escape"];
    this.visualViewport = null;
    this.handleViewportChange = this.handleViewportChange.bind(this);
    this.handlePanelFocusIn = this.handlePanelFocusIn.bind(this);
  }

  afterMount() {
    const requestedState =
      this.el.dataset.open === undefined
        ? this.el.dataset.state || "closed"
        : this.el.dataset.open === "true"
          ? "open"
          : "closed";

    if (requestedState === this.state) {
      if (this.state === "open") {
        this.activateOpenState();

        // The server rendered the dialog already open; report it once, the way
        // the closed -> open transition would have.
        this.pushEvent("open");
      }
      return;
    }

    this.transition(requestedState === "open" ? "open" : "close");
  }

  // A LiveView patch of the dialog's contents (a provider select, a form
  // field, a list that changed) must not destroy and re-create the component:
  // doing so replays the enter animation and steals focus, which reads as the
  // modal "reloading". Reinitialize only when the server actually asked for a
  // state change or changed the component's configuration.
  skipReinitialize(el) {
    return (
      this.state === "open" &&
      el.dataset.open !== "false" &&
      el.dataset.options === this._optionsRaw &&
      el.dataset.eventMappings === this._eventMappingsRaw
    );
  }

  // The server renders data-state and hidden, so a LiveView patch preserves
  // the open state; only the aria-* attributes this component adds can be
  // stripped. Re-apply those, and put focus back inside the dialog if the
  // patch replaced the focused element.
  afterUpdate() {
    this.ariaManager.applyAriaAttributes(this.stateMachine.state);

    if (document.activeElement === document.body) {
      this.el.focus();
    }
  }

  getComponentConfig() {
    return {
      stateMachine: {
        closed: {
          enter: "onClosedEnter",
          exit: "onClosedExit",
          transitions: {
            open: "open",
          },
        },
        open: {
          enter: "onOpenEnter",
          exit: "onOpenExit",
          transitions: {
            close: "closed",
          },
        },
      },
      events: {
        closed: {
          keyMap: {},
        },
        open: {
          keyMap: {
            ...(this.options.closeOnEscape === false
              ? {}
              : { Escape: "close" }),
          },
        },
      },
      hiddenConfig: {
        closed: {
          content: true,
        },
        open: {
          content: false,
        },
      },
      ariaConfig: {
        content: {
          open: {
            hidden: "false",
          },
          closed: {
            hidden: "true",
          },
        },
        "content-panel": {
          all: {
            role: this.options.role || "dialog",
          },
          open: {
            modal: "true",
            labelledby: () => this.getPartId("title"),
            describedby: () => this.getPartId("description"),
          },
          closed: {
            modal: null,
            labelledby: null,
            describedby: null,
          },
        },
        "close-trigger": {
          all: {
            label: "Close dialog",
          },
        },
      },
    };
  }

  // Setup component events
  setupComponentEvents() {
    super.setupComponentEvents();

    this.contentPanel?.addEventListener("focusin", this.handlePanelFocusIn);

    // Only setup click handler if closeOnOutsideClick is enabled
    if (this.options.closeOnOutsideClick) {
      this.setupOutsideClickDetection();
    }
  }

  setupOutsideClickDetection() {
    // Create click outside monitor to handle clicks on the overlay
    this.clickOutsideMonitor = new ClickOutsideMonitor(
      [this.contentPanel],
      (event) => {
        // Only close if click was directly on the content container (overlay area)
        if (
          event.target === this.content ||
          event.target.dataset.part === "overlay"
        ) {
          this.transition("close");
        }
      },
    );
  }

  teardownComponentEvents() {
    super.teardownComponentEvents();

    this.contentPanel?.removeEventListener("focusin", this.handlePanelFocusIn);
    this.unbindVisualViewport();

    // Clean up click outside monitor
    this.clickOutsideMonitor?.destroy();
    this.clickOutsideMonitor = null;
  }

  // State machine handlers
  onClosedEnter() {
    // Content hides after its exit animation completes.
  }

  onClosedExit() {
    // No special handling needed
  }

  onOpenEnter() {
    this.activateOpenState();

    // Notify the server of the state change
    this.pushEvent("open");
  }

  onOpenExit() {
    this.unbindVisualViewport();
    this.resetPanelViewportStyles();
    this.focusTrap?.deactivate();
    this.clickOutsideMonitor?.stop();

    // Notify before an exit animation or a LiveView patch can destroy this instance.
    this.pushEvent("close");
  }

  activateOpenState() {
    // Initialize focus trap if not already created
    this.el.focus();
    if (!this.focusTrap) {
      this.focusTrap = new FocusTrap(this.contentPanel);
    }

    // Activate focus trap
    this.focusTrap.activate();

    // Activate click outside monitor if enabled
    if (this.clickOutsideMonitor) {
      this.clickOutsideMonitor.start();
    }

    this.bindVisualViewport();
    this.syncPanelToVisualViewport();

    // Escape handling uses the component key map.
  }

  handlePanelFocusIn() {
    // Focusing the first field is what summons the keyboard; the visual
    // viewport resize follows and keeps the panel in view.
    this.syncPanelToVisualViewport();
  }

  bindVisualViewport() {
    if (!this.isCompactViewport() || !window.visualViewport || this.visualViewport) {
      return;
    }

    this.visualViewport = window.visualViewport;
    this.visualViewport.addEventListener("resize", this.handleViewportChange);
    this.visualViewport.addEventListener("scroll", this.handleViewportChange);
  }

  unbindVisualViewport() {
    if (!this.visualViewport) return;

    this.visualViewport.removeEventListener("resize", this.handleViewportChange);
    this.visualViewport.removeEventListener("scroll", this.handleViewportChange);
    this.visualViewport = null;
  }

  handleViewportChange() {
    this.syncPanelToVisualViewport();
  }

  syncPanelToVisualViewport() {
    if (
      !this.isCompactViewport() ||
      !this.visualViewport ||
      !this.contentPanel ||
      this.state !== "open"
    ) {
      return;
    }

    const margin = 16;
    const viewport = this.visualViewport;

    // The panel is centred in the *visible* area. `top: 50%` resolves against
    // the layout viewport, which does not move when the keyboard opens — the
    // visual viewport does — so the panel is nudged with `top`.
    //
    // The nudge must never be a transform: Tailwind centres the panel with
    // the `translate` property, and a transform on top of it is a second
    // translation, which pushed half of the panel off the screen.
    const visibleCentre = viewport.offsetTop + viewport.height / 2;
    const layoutCentre = window.innerHeight / 2;
    const shift = Math.round(visibleCentre - layoutCentre);

    this.contentPanel.style.maxHeight = `${Math.max(
      160,
      viewport.height - margin * 2,
    )}px`;

    // A visual viewport narrower than the layout viewport (rotated or zoomed)
    // must not be overflowed by the panel.
    if (viewport.width < window.innerWidth - 1) {
      this.contentPanel.style.maxWidth = `${Math.max(
        240,
        viewport.width - margin * 2,
      )}px`;
    } else {
      this.contentPanel.style.maxWidth = "";
    }

    this.contentPanel.style.top = `calc(50% + ${shift}px)`;
  }

  resetPanelViewportStyles() {
    if (!this.contentPanel) return;

    this.contentPanel.style.maxHeight = "";
    this.contentPanel.style.maxWidth = "";
    this.contentPanel.style.top = "";
  }

  isCompactViewport() {
    return (
      typeof window !== "undefined" &&
      window.matchMedia?.("(max-width: 640px)").matches
    );
  }

  beforeDestroy() {
    // Clean up focus trap
    this.focusTrap?.destroy();
    this.focusTrap = null;
    this.unbindVisualViewport();
    this.resetPanelViewportStyles();
  }
}

// Register the component
SaladUI.register("dialog", DialogComponent);

export default DialogComponent;
