import { test, expect } from '@playwright/test';

// The app is installable: it has a manifest, root-scoped icons, and a service
// worker that registers. Nothing here asserts offline editing — the editor
// needs the server — only the pieces the browser uses to offer "Install app".
test.describe('installable app', () => {
  test('serves a manifest and registers the service worker', async ({ page }) => {
    await page.goto('/canvas');

    await expect(page.locator('link[rel="manifest"]')).toHaveAttribute(
      'href',
      '/manifest.webmanifest',
    );
    await expect(page.locator('link[rel="apple-touch-icon"]')).toHaveCount(1);

    const response = await page.request.get('/manifest.webmanifest');
    expect(response.ok()).toBeTruthy();

    const manifest = await response.json();
    expect(manifest.display).toBe('standalone');
    expect(manifest.start_url).toBe('/canvas');
    expect(manifest.icons.map((icon: { purpose: string }) => icon.purpose)).toEqual(
      expect.arrayContaining(['any', 'maskable']),
    );

    // Registration waits for the load event, so poll rather than reading once.
    await expect
      .poll(
        () =>
          page.evaluate(async () =>
            Boolean(await navigator.serviceWorker.getRegistration('/')),
          ),
        { timeout: 10_000 },
      )
      .toBe(true);

    // The install event precached the offline shell.
    const cachesReady = await page.evaluate(async () => {
      const names = await caches.keys();
      return names.some((name) => name.startsWith('psc-shell-'));
    });

    expect(cachesReady).toBe(true);
  });
});
