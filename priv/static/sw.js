// The service worker is what makes the app installable and gives it a sane
// offline fallback. It is deliberately not offline-first: every LiveView
// interaction needs the websocket and the server, so an offline canvas would
// be a lie. What is cached is the shell that can be shown when the network is
// gone.
//
// Bump VERSION on a release that changes the offline page or icons; the
// activate handler drops every cache that does not carry the current version.
const VERSION = "v1";
const SHELL_CACHE = `psc-shell-${VERSION}`;
const ASSET_CACHE = `psc-assets-${VERSION}`;
const OFFLINE_URL = "/offline.html";
const PRECACHE = [OFFLINE_URL, "/images/icon-192.png", "/images/icon-512.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(SHELL_CACHE)
      .then((cache) => cache.addAll(PRECACHE))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== SHELL_CACHE && key !== ASSET_CACHE)
            .map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;

  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // Third-party requests are none of our business, and neither are the
  // LiveView transports (a websocket is not interceptable, but the long-poll
  // fallback would still pass through here).
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith("/live")) return;

  if (request.mode === "navigate") {
    event.respondWith(networkFirstNavigation(request));
    return;
  }

  if (
    url.pathname.startsWith("/assets/") ||
    url.pathname.startsWith("/images/")
  ) {
    event.respondWith(networkFirstAsset(request));
  }
});

// Documents stay network-only: a cached authenticated page could be shown
// after sign-out, and a cached login page to a signed-in user. The cache is a
// fallback for the offline case, nothing else.
async function networkFirstNavigation(request) {
  try {
    return await fetch(request);
  } catch (_error) {
    const offline = await caches.match(OFFLINE_URL);
    return offline || Response.error();
  }
}

// Assets are network-first on purpose: in development the JavaScript and CSS
// are served from stable paths, so a cache-first worker would keep serving the
// previous build until the cache version changed. The cache is a fallback for
// when the network is gone, not the primary source.
async function networkFirstAsset(request) {
  try {
    const response = await fetch(request);

    if (response.ok && response.type === "basic") {
      const cache = await caches.open(ASSET_CACHE);
      cache.put(request, response.clone());
    }

    return response;
  } catch (_error) {
    const cached = await caches.match(request);
    return cached || Response.error();
  }
}
