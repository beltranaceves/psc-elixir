// Keeps a <details> element open (or closed) across LiveView patches.
//
// The open state is a browser concern here: the server only supplies the
// default, and collapsing/expanding happens client-side. Without this, a
// periodic save or a form change would reset the element and close the file
// editor inside it.
export default {
  mounted() {
    this.open = this.el.open
  },

  beforeUpdate() {
    this.open = this.el.open
  },

  updated() {
    this.el.open = this.open
  },
}
