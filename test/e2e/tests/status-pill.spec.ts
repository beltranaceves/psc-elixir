import { test, expect, devices } from '@playwright/test';

/**
 * The canvas editor's status pill on a touch device.
 *
 * The pill reports the save state, and a tooltip with the details (last saved,
 * write attempts). A phone has no hover, so the tooltip is opened by a tap —
 * this file therefore runs with a real touch device profile, which the
 * desktop project cannot do (a device profile forces its own worker, so it
 * has to be top-level in a file of its own).
 */

test.use({
  ...devices['iPhone 13'],
  // The iPhone profile defaults to WebKit, which is not installed here; the
  // touch emulation is what matters, and Chromium reports `hover: none` for
  // it just the same.
  defaultBrowserType: 'chromium',
});

function uniqueName(label: string): string {
  return `${label} ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

async function createCanvasAndOpen(page: import('@playwright/test').Page, name: string) {
  await page.goto('/canvas');
  await page.locator('.phx-connected').first().waitFor();

  // The helpers need a canvas with structure to edit: the PSC card, not the
  // default blank (which is empty until the owner builds it in place).
  await page.getByRole('button', { name: 'Start from the PSC canvas' }).click();
  await page.getByPlaceholder('Enter canvas name...').fill(name);
  await page.getByRole('button', { name: 'Create Canvas' }).click();

  // Creating lands the user in the canvas they asked for.
  await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
  await expect(page.locator('#canvas-name-form')).toBeVisible();
  // The tab strip switches client-side and patches the server; clicking a tab
  // before the socket is up gets the first render's Editor tab patched back
  // over the choice.
  await page.locator('.phx-connected').first().waitFor();

  const close = page.locator('#flash-group').getByRole('button', { name: 'close' }).first();
  if (await close.isVisible().catch(() => false)) {
    await close.click();
  }
}

test.describe('canvas editor status pill on a phone', () => {
  test('a tap opens the status tooltip', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Status Tap'));

    const pill = page.locator('#canvas-save-state-compact');
    const tip = page.locator('#canvas-save-state-compact-tooltip [data-part="content"]');

    await expect(pill).toBeVisible();
    await expect(tip).toBeHidden();

    // A touch device has no hover, so the tap opens the tooltip.
    await pill.tap();
    await expect(tip).toBeVisible();
    await expect(tip).toContainText('Last saved');
    await expect(tip).toContainText('Writes this session');

    // A second tap closes it again.
    await pill.tap();
    await expect(tip).toBeHidden();
  });
});
