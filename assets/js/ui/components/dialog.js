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
    this.panelVisibilityTimer = null;
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
      }
      return;
    }

    this.transition(requestedState === "open" ? "open" : "close");
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
    clearTimeout(this.panelVisibilityTimer);
    this.panelVisibilityTimer = null;

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
    clearTimeout(this.panelVisibilityTimer);
    this.panelVisibilityTimer = null;
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
    this.schedulePanelVisibility();

    // Escape handling uses the component key map.
  }

  handlePanelFocusIn() {
    this.schedulePanelVisibility();
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

  schedulePanelVisibility() {
    if (!this.isCompactViewport()) return;

    clearTimeout(this.panelVisibilityTimer);
    this.panelVisibilityTimer = setTimeout(() => {
      if (this.destroyed || this.state !== "open" || !this.contentPanel) return;

      this.contentPanel.scrollIntoView({ block: "center", inline: "nearest" });
      this.syncPanelToVisualViewport();
    }, 75);
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
    const viewportTop = this.visualViewport.offsetTop + margin;
    const viewportBottom =
      this.visualViewport.offsetTop + this.visualViewport.height - margin;

    this.contentPanel.style.maxHeight = `${Math.max(
      160,
      this.visualViewport.height - margin * 2,
    )}px`;

    const rect = this.contentPanel.getBoundingClientRect();
    let shift = 0;

    if (rect.bottom > viewportBottom) {
      shift = viewportBottom - rect.bottom;
    } else if (rect.top < viewportTop) {
      shift = viewportTop - rect.top;
    }

    this.contentPanel.style.transform =
      shift === 0 ? "" : `translate(-50%, calc(-50% + ${Math.round(shift)}px))`;
  }

  resetPanelViewportStyles() {
    if (!this.contentPanel) return;

    this.contentPanel.style.maxHeight = "";
    this.contentPanel.style.transform = "";
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
    clearTimeout(this.panelVisibilityTimer);
    this.panelVisibilityTimer = null;
    this.resetPanelViewportStyles();
  }
}

// Register the component
SaladUI.register("dialog", DialogComponent);

export default DialogComponent;
