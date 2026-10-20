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

async function dismissFlash(page: import('@playwright/test').Page): Promise<void> {
  const close = page.locator('#flash-group').getByRole('button', { name: 'close' }).first();
  if (await close.isVisible().catch(() => false)) {
    await close.click();
    await expect(close).toBeHidden();
  }
}

async function createCanvasAndOpen(page: import('@playwright/test').Page, name: string) {
  await page.goto('/canvas');
  await page.locator('.phx-connected').first().waitFor();

  await page.getByPlaceholder('Enter canvas name...').fill(name);
  await page.getByRole('button', { name: 'Create Canvas' }).click();

  // The success flash auto-dismisses, so it is not a reliable assertion.
  // The new card is durable proof that the creation round trip landed.
  // The list holds every canvas, and the tests run in parallel, so the card
  // is found by name rather than by position.
  const card = page
    .getByRole('heading', { name })
    .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
  await expect(card).toBeVisible({ timeout: 15_000 });

  await dismissFlash(page);

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

  test('one status pill reports the note and the canvas', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('One Pill'));

    await page.locator('#canvas-tab-notes').click();
    await page.locator('#new-note-button').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();

    // There is one pill, not one per surface: the note editor has none of its
    // own.
    await expect(page.locator('#canvas-save-state-pill')).toHaveCount(1);
    await expect(page.locator('#canvas-note-status')).toHaveCount(0);

    // It reports the note, and lists the canvas alongside it.
    const tip = page.locator('#canvas-save-state-pill-tooltip [data-part="content"]');
    await page.locator('#canvas-save-state-pill').hover();
    await expect(tip).toBeVisible();
    await expect(tip).toContainText('Note');
    await expect(tip).toContainText('Canvas');
    await expect(tip).toContainText('Writes this session');
  });

  test('the pill reports the canvas when no note is open', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Canvas Pill'));

    await page.locator('#canvas-tab-editor').click();
    await expect(page.locator('#canvas-grid')).toBeVisible();

    const tip = page.locator('#canvas-save-state-pill-tooltip [data-part="content"]');
    await page.locator('#canvas-save-state-pill').hover();
    await expect(tip).toBeVisible();
    // One surface, so no section heading.
    await expect(tip).not.toContainText('Canvas');
    await expect(tip).toContainText('Writes this session');
  });

  test('a template can carry notes, and a canvas inherits them', async ({ page }) => {
    const templateName = uniqueName('Notes Template');

    // The template designer authors the notes.
    await page.goto('/templates/new');
    await page.locator('.phx-connected').first().waitFor();
    await page.getByRole('button', { name: 'Add Column' }).click();
    await page.getByRole('button', { name: 'Add Row' }).click();
    await page.getByRole('button', { name: 'Add note' }).click();

    await page.locator('#template-notes input[name="value"]').first().fill('Framing questions');

    // The note editor starts as a rendered preview; click it to open the textarea.
    await page.locator('#template-notes [data-editor-preview]').first().click();
    await page
      .locator('#template-notes textarea[name="content"]')
      .first()
      .fill('What is the actual problem?');

    await page.locator('#template-form input[name="name"]').fill(templateName);
    await page.getByRole('button', { name: 'Save Template' }).click();
    await page.waitForURL(/\/templates$/);

    // A canvas made from it starts with the note.
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();
    const canvasName = uniqueName('Inherited Notes');
    await page.getByPlaceholder('Enter canvas name...').fill(canvasName);
    await page.getByLabel('Start from').selectOption({ label: templateName });
    await page.getByRole('button', { name: 'Create Canvas' }).click();

    const card = page
      .getByRole('heading', { name: canvasName })
      .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
    await expect(card).toBeVisible({ timeout: 15_000 });
    await dismissFlash(page);

    await card.getByRole('link', { name: 'Edit' }).click();
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);

    await page.locator('#canvas-tab-notes').click();
    await expect(page.locator('#canvas-notes-items')).toContainText('Framing questions');
    await expect(page.locator('#canvas-notes-items')).toContainText(
      'What is the actual problem?',
    );
  });

  test('a scratchpad template gives a canvas one note and no list', async ({ page }) => {
    await page.goto('/templates/new');
    await page.locator('.phx-connected').first().waitFor();

    const templateName = uniqueName('Scratchpad Tpl');

    // The designer picks the note mode.
    await page.locator('#notes-mode-single').click();
    await expect(page.locator('#notes-mode-single')).toHaveAttribute('aria-pressed', 'true');

    await page.getByRole('button', { name: 'Add Column' }).click();
    await page.getByRole('button', { name: 'Add Row' }).click();
    await page.locator('#template-form input[name="name"]').fill(templateName);
    await page.getByRole('button', { name: 'Save Template' }).click();
    await page.waitForURL(/\/templates$/);

    // A canvas made from it is a scratchpad.
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();
    const canvasName = uniqueName('Scratchpad Canvas');
    await page.getByPlaceholder('Enter canvas name...').fill(canvasName);
    await page.getByLabel('Start from').selectOption({ label: templateName });
    await page.getByRole('button', { name: 'Create Canvas' }).click();

    const card = page
      .getByRole('heading', { name: canvasName })
      .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
    await expect(card).toBeVisible({ timeout: 15_000 });
    await dismissFlash(page);

    await card.getByRole('link', { name: 'Edit' }).click();
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);

    await page.locator('#canvas-tab-notes').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();

    // One note, no list, no way to create another.
    await expect(page.locator('#canvas-notes-list')).toHaveCount(0);
    await expect(page.locator('#new-note-button')).toHaveCount(0);
    await expect(page.locator('#canvas-note-delete')).toHaveCount(0);
    await expect(page.locator('#canvas-notes-back')).toHaveCount(0);
  });
});
