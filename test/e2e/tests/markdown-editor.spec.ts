import { test, expect } from '@playwright/test';

/**
 * The reusable Markdown editor.
 *
 * It starts as a preview: a click on the rendered Markdown opens the textarea,
 * and blurring it re-renders the preview. There is no "Markdown preview" /
 * "Editing Markdown" banner above it — it said what was already obvious.
 */

function uniqueName(label: string): string {
  return `${label} ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

async function createCanvasAndOpen(page: import('@playwright/test').Page, name: string) {
  await page.goto('/canvas');
  await page.locator('.phx-connected').first().waitFor();

  await page.getByPlaceholder('Enter canvas name...').fill(name);
  await page.getByRole('button', { name: 'Create Canvas' }).click();
  await expect(page.locator('#flash-group')).toContainText('Canvas created successfully');

  const card = page
    .getByRole('heading', { name })
    .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
  await card.getByRole('link', { name: 'Edit' }).click();
  await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
  await expect(page.locator('#canvas-name-form')).toBeVisible();
}

test.describe('the Markdown editor', () => {
  test('has no mode banner', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('No Banner'));

    await page.locator('#canvas-tab-notes').click();
    await page.locator('#new-note-button').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();

    await expect(page.locator('[data-editor-mode]')).toHaveCount(0);
    await expect(page.locator('[data-editor-hint]')).toHaveCount(0);
  });

  test('switches between the preview and the raw Markdown', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Editor Modes'));

    await page.locator('#canvas-tab-notes').click();
    await page.locator('#new-note-button').click();

    const preview = page.locator('#canvas-note-preview');
    await expect(preview).toBeVisible();

    // A click on the rendered Markdown opens the textarea.
    await preview.click({ force: true });
    await expect(page.locator('#canvas-note-input')).toBeVisible();
    await expect(preview).toBeHidden();

    // Blurring it goes back to the preview.
    await page.locator('#canvas-note-input').blur();
    await expect(preview).toBeVisible();
  });

  test('the focus indication follows the rounded frame, not the square textarea', async ({
    page,
  }) => {
    await createCanvasAndOpen(page, uniqueName('Rounded Focus'));

    await page.locator('#canvas-tab-notes').click();
    await page.locator('#new-note-button').click();

    const textarea = page.locator('#canvas-note-input');
    const frame = page.locator('#canvas-note-markdown');

    // Does the element paint a visible shadow? A ring is a shadow layer with
    // a size; the transparent leftovers of a ring utility are all zeroes.
    const paintsRing = (locator: import('@playwright/test').Locator) =>
      locator.evaluate((el) => {
        const shadow = getComputedStyle(el).boxShadow;
        if (!shadow || shadow === 'none') return false;
        return shadow.split(/,(?![^()]*\))/).some((layer) => {
          // The sizes come after the colour, so read them from there.
          const sizes = layer
            .slice(layer.lastIndexOf(')') + 1)
            .match(/([\d.]+)px\s+([\d.]+)px\s+([\d.]+)px\s+([\d.]+)px/);
          if (!sizes) return false;
          return sizes.slice(1).some((value) => parseFloat(value) > 0);
        });
      });

    expect(await paintsRing(textarea)).toBe(false);

    await page.locator('#canvas-note-preview').click({ force: true });
    await expect(textarea).toBeVisible();

    // Focusing must not make the textarea paint a ring of its own: it has
    // square corners, and a ring on it cuts across the frame's rounded
    // corners.
    expect(await paintsRing(textarea)).toBe(false);

    // The frame carries the focus indication, and it is rounded.
    expect(await paintsRing(frame)).toBe(true);
    const radius = await frame.evaluate(
      (el) => getComputedStyle(el).borderRadius,
    );
    expect(parseFloat(radius)).toBeGreaterThan(0);
  });
});
