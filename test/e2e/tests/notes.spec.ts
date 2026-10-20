import { test, expect } from '@playwright/test';

/**
 * The Notes view of the canvas editor.
 *
 * A note is collaborative Markdown that belongs to a canvas. It inherits the
 * canvas's access rules: there is no share control on a note, because sharing
 * the canvas shares its notes.
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

  // The list holds every canvas, and the tests run in parallel, so the card
  // is found by name rather than by position.
  const card = page
    .getByRole('heading', { name })
    .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
  await card.getByRole('link', { name: 'Edit' }).click();
  await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
  await expect(page.locator('#canvas-name-form')).toBeVisible();
}

test.describe('canvas notes', () => {
  test('creates a note, writes in it and keeps it after a reload', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Notes Canvas'));

    // Open the Notes view.
    await page.locator('#canvas-tab-notes').click();
    await expect(page.locator('#canvas-notes-empty')).toBeVisible();

    // Create a note: it opens straight away and its id is in the URL.
    await page.locator('#new-note-button').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();
    await expect(page).toHaveURL(/tab=notes&note=/);

    // Name it.
    const title = page.locator('#canvas-note-title-form input');
    await title.fill('Research notes');
    await title.blur();
    await expect(page.locator('#canvas-notes-items')).toContainText('Research notes');

    // Write in it.
    const preview = page.locator('#canvas-note-preview');
    await expect(preview).toBeVisible();
    await preview.click();
    const textarea = page.locator('#canvas-note-input');
    await textarea.fill('A finding worth keeping');
    await textarea.blur();

    await expect(preview).toContainText('A finding worth keeping', { timeout: 15_000 });

    // The content survives a reload.
    await page.reload();
    await page.locator('.phx-connected').first().waitFor();
    await expect(page.locator('#canvas-note-preview')).toContainText('A finding worth keeping');
  });

  test('shows the list of notes and opens the one that is chosen', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Notes List'));

    await page.locator('#canvas-tab-notes').click();
    await page.locator('#new-note-button').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();

    await page.locator('#canvas-note-title-form input').fill('First');
    await page.locator('#canvas-note-title-form input').blur();
    await page.locator('#new-note-button').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();
    await page.locator('#canvas-note-title-form input').fill('Second');
    await page.locator('#canvas-note-title-form input').blur();

    await expect(page.locator('#canvas-notes-items li')).toHaveCount(2);

    // Choosing a note in the list opens it. The list is ordered by the most
    // recently touched, so the note is chosen by name rather than by position.
    await page.locator('#canvas-notes-items').getByRole('button', { name: /^First/ }).click();
    await expect(page.locator('#canvas-note-title-form input')).toHaveValue('First');
  });

  test('the page does not scroll on a phone', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createCanvasAndOpen(page, uniqueName('Notes Phone'));

    await page.locator('#canvas-tab-bar-notes').click();
    await expect(page.locator('#canvas-notes-empty')).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollHeight - document.documentElement.clientHeight,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test('a note is deleted by the canvas owner', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Notes Delete'));

    await page.locator('#canvas-tab-notes').click();
    await page.locator('#new-note-button').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();

    await page.locator('#canvas-note-delete').click();
    await expect(page.locator('#canvas-notes-empty')).toBeVisible();
  });
});
