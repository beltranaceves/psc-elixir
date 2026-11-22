// Turns the off-screen export render of a canvas into a PNG or SVG download.
//
// The LiveView renders `#canvas-export` (a read-only copy of the board at a
// fixed width, see UnstrCanvasLive.Editor's export_board) only while an export
// runs. This hook snapshots it with modern-screenshot, downloads the file and
// tells the server it is done, which removes the render again.
//
// The SVG wraps the board's HTML in a <foreignObject>: it is sharp at any zoom
// in a browser, but design tools that do not support foreignObject cannot
// open it as vector shapes.
import {domToBlob, domToForeignObjectSvg} from "../../vendor/modern-screenshot.mjs"

// Browsers refuse canvases past roughly 16 million pixels (Safari's limit is
// the strictest), so a large board is exported at a lower scale.
const MAX_PIXELS = 16_000_000
const PREFERRED_SCALE = 2

export default {
  mounted() {
    this.run()
  },

  async run() {
    const sheet = this.el.querySelector("[data-export-sheet]")
    const format = this.el.dataset.format
    const filename = this.el.dataset.filename || `canvas.${format}`

    try {
      await waitForImages(sheet)

      const width = sheet.offsetWidth
      const height = sheet.offsetHeight
      const options = {
        width,
        height,
        backgroundColor: getComputedStyle(sheet).backgroundColor,
        // A picture that cannot be read (another site without CORS, in a
        // field's Markdown) becomes a blank instead of failing the export.
        fetch: {placeholderImage: TRANSPARENT_PIXEL},
      }

      const blob =
        format === "svg"
          ? await svgBlob(sheet, options)
          : await domToBlob(sheet, {...options, type: "image/png", scale: scaleFor(width, height)})

      download(blob, filename)
      this.pushEvent("export_finished", {ok: true})
    } catch (error) {
      console.error("Canvas export failed", error)
      this.pushEvent("export_finished", {ok: false})
    }
  },
}

const TRANSPARENT_PIXEL =
  "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

function scaleFor(width, height) {
  const area = Math.max(1, width * height)
  return Math.min(PREFERRED_SCALE, Math.sqrt(MAX_PIXELS / area))
}

// The library's domToSvg rasterises first and wraps a PNG in the SVG; the
// foreignObject SVG keeps the board as HTML, so text stays sharp and selectable.
async function svgBlob(node, options) {
  const svg = await domToForeignObjectSvg(node, options)
  const markup = new XMLSerializer()
    .serializeToString(svg)
    .replace(/[\u0000-\u0008\v\f\u000E-\u001F\uFFFE\uFFFF]/gu, "")

  return new Blob(['<?xml version="1.0" encoding="UTF-8"?>\n', markup], {type: "image/svg+xml"})
}

// The backdrop (fetched through our server for another site's picture) must
// have loaded, or the snapshot would draw an empty board.
function waitForImages(root) {
  const pending = [...root.querySelectorAll("img")]
    .filter(img => !img.complete)
    .map(img => new Promise(resolve => {
      img.addEventListener("load", resolve, {once: true})
      img.addEventListener("error", resolve, {once: true})
    }))

  return Promise.all(pending)
}

function download(blob, filename) {
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
