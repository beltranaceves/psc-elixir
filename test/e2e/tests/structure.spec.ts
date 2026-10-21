import { test, expect } from '@playwright/test';

/**
 * Structure editing: the owner's Edit structure toggle, and the truly blank
 * canvas built in place.
 *
 * A canvas is no longer frozen at the shape it was instantiated with. The
 * owner can add, remove, rename and accent rows and columns, and rename
 * cells, add and remove fields, and retitle sections — every change an
 * operation that lands on every connected client.
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

// Creates a canvas from the picker's PSC card and opens its editor.
async function createPscCanvasAndOpen(page: import('@playwright/test').Page, name: string) {
  await page.goto('/canvas');
  await page.locator('.phx-connected').first().waitFor();

  await page.getByRole('button', { name: 'Start from Problem–Solution Canvas' }).click();
  await page.getByPlaceholder('Enter canvas name...').fill(name);
  await page.getByRole('button', { name: 'Create Canvas' }).click();

  await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
  await page.locator('.phx-connected').first().waitFor();
  await dismissFlash(page);
}

test.describe('canvas structure editing', () => {
  test('a blank canvas is built in place and survives a reload', async ({ page }) => {
    const name = uniqueName('Built Blank');

    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();

    // Blank is the default selection.
    await page.getByPlaceholder('Enter canvas name...').fill(name);
    await page.getByRole('button', { name: 'Create Canvas' }).click();
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    await page.locator('.phx-connected').first().waitFor();
    await dismissFlash(page);

    // The empty state, with the owner's build actions.
    await expect(page.locator('#canvas-grid')).toContainText('This canvas has no structure yet.');
    await page.locator('#empty-add-row').click();
    await page.locator('#empty-add-column').click();

    // The grid renders once the structure exists; the empty state's buttons
    // go with it, and more structure waits for the Edit structure toggle.
    await expect(page.locator('#canvas-grid table')).toBeVisible();
    await expect(page.locator('#empty-add-column')).toHaveCount(0);

    // Rename a row and a column while Edit structure is on. In edit mode the
    // headers are inputs, so the names are their values — but a fill passes
    // its own assertion instantly, so the wait that matters is the save pill
    // returning to Saved: the debounce has fired, the operations have landed
    // and the idle save has folded them. Only then is a reload safe.
    await page.locator('#edit-structure-toggle').click();
    await page.locator('#row-r1-label-form input[name="label"]').fill('Rationale');
    await page.locator('#column-c1-label-form input[name="label"]').fill('Perceive');
    await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved', {
      timeout: 10_000,
    });

    // The structure survives a reload: the folded snapshot carries it.
    await page.reload({ waitUntil: 'networkidle' });
    await page.locator('.phx-connected').first().waitFor();
    await page.locator('#edit-structure-toggle').click();
    await expect(page.locator('#row-r1-label-form input[name="label"]')).toHaveValue('Rationale');
    await expect(page.locator('#column-c1-label-form input[name="label"]')).toHaveValue('Perceive');
  });

  test('removing a row with content asks first, and the confirm removes it', async ({ page }) => {
    await createPscCanvasAndOpen(page, uniqueName('Confirmed Removal'));

    // Fill a cell in the last row, so removing it is destructive. The house
    // editCell pattern: wait for the hook's initial render, click the display,
    // fill, blur — the blur asks the server to re-render the preview.
    const display = page.locator('#md-render-manifestations-content');
    await expect(display).toContainText('Click to edit', { timeout: 15_000 });
    await display.click();
    await page.locator('#md-manifestations-content textarea').fill('precious work');
    await page.locator('#md-manifestations-content textarea').blur();
    await expect(display).toContainText('precious work', { timeout: 15_000 });

    await page.locator('#edit-structure-toggle').click();
    await page
      .locator("button[phx-click='request_remove_row'][phx-value-id='tactics']")
      .click();

    const dialog = page.locator('#remove-structure-dialog [data-part="content-panel"]');
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText('Remove this row?');

    // Keeping it removes nothing.
    await dialog.getByRole('button', { name: 'Keep it' }).click();
    await expect(dialog).toBeHidden();
    await expect(page.locator('#cell-card-manifestations')).toBeVisible();

    // Removing it does.
    await page
      .locator("button[phx-click='request_remove_row'][phx-value-id='tactics']")
      .click();
    await dialog.getByRole('button', { name: 'Remove' }).click();
    await expect(dialog).toBeHidden();
    await expect(page.locator('#cell-card-manifestations')).toHaveCount(0);
    await expect(page.locator('#canvas-grid tbody')).not.toContainText('Tactics');
  });

  test('removing an empty column goes straight away', async ({ page }) => {
    await createPscCanvasAndOpen(page, uniqueName('Quick Removal'));

    await page.locator('#edit-structure-toggle').click();
    await page
      .locator("button[phx-click='request_remove_column'][phx-value-id='learn']")
      .click();

    // No confirm: the column holds nothing.
    await expect(page.locator('#remove-structure-dialog')).toHaveCount(0);
    await expect(page.locator('#canvas-grid thead')).not.toContainText('Learn');
  });

  test('cells gain and lose fields in place', async ({ page }) => {
    await createPscCanvasAndOpen(page, uniqueName('Field Work'));

    await page.locator('#edit-structure-toggle').click();
    await page.locator('#cell-add-field-problem input[name="field"]').fill('notes');
    await page.locator('#cell-add-field-problem').getByRole('button', { name: 'Add' }).click();

    // The new field renders with its own editor and an untitled section.
    await expect(page.locator('#cell-field-problem-notes')).toBeVisible();
    await expect(page.locator('#cell-title-problem-notes input[name="title"]')).toHaveValue('');

    // Retitle it — in edit mode the title input is the section's label — then
    // remove it.
    await page.locator('#cell-title-problem-notes input[name="title"]').fill('Notes');
    await expect(page.locator('#cell-title-problem-notes input[name="title"]')).toHaveValue(
      'Notes',
    );

    await page
      .locator("button[phx-click='remove_cell_field'][phx-value-cell_key='problem'][phx-value-field='notes']")
      .click();
    await expect(page.locator('#cell-field-problem-notes')).toHaveCount(0);
  });
});
