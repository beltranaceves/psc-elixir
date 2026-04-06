export default {
  mounted() {
    this.currentUserId = this.el.dataset.currentUserId;
    
    // Initialize textarea with the value attribute from the server
    // The textarea has phx-update="ignore" so we need to set it manually
    const initialValue = this.el.getAttribute('value');
    if (initialValue) {
      this.el.value = initialValue;
    }
    
    this.handleEvent("content_updated", ({ newContent, fromUserId }) => {
      // Special case: resync from server (fromUserId = -1)
      // Always apply server resyncs regardless of focus state
      const isServerResync = fromUserId == -1;
      
      // Skip update only if:
      // 1. NOT a server resync, AND
      // 2. Update is from the current user, AND  
      // 3. User is actively editing
      if (!isServerResync && this.currentUserId == fromUserId && document.activeElement === this.el) {
        // Skip - user is editing and this is their own change
        return;
      }
      
      // Get current cursor position to restore it after update
      const cursorPos = this.el.selectionStart;
      
      // Update the textarea value
      this.el.value = newContent;
      
      // Restore cursor position if it's still valid
      if (cursorPos <= newContent.length) {
        this.el.setSelectionRange(cursorPos, cursorPos);
      }
      
      // If this is a server resync, show a subtle notification
      if (isServerResync) {
        console.log("Document synced with server for consistency");
      }
    });
  }
};
