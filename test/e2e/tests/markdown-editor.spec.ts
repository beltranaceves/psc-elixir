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
});
