import { test, expect } from '@playwright/test';

/**
 * Image boards end to end.
 *
 * An image board pins cells to percentages of a backdrop picture, so the
 * browser is the only place the geometry is actually laid out. These tests
 * cover what the server cannot see: the picture frame, the percentage
 * placement, the drag/resize handles and the keyboard path.
 */

function uniqueName(label: string): string {
  return `${label} ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

async function createImageAndOpen(page: import('@playwright/test').Page, name: string) {
  await page.goto('/canvas');
  await page.locator('.phx-connected').first().waitFor();

  // The built-in Image Board is a card in the picker like any template.
  await page.getByRole('button', { name: 'Start from Image Board' }).click();
  await page.getByPlaceholder('Enter canvas name...').fill(name);
  await page.getByRole('button', { name: 'Create Canvas' }).click();

  await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
  await expect(page.locator('#canvas-image')).toBeVisible();
  await page.locator('.phx-connected').first().waitFor();

  const close = page.locator('#flash-group').getByRole('button', { name: 'close' }).first();
  if (await close.isVisible().catch(() => false)) {
    await close.click();
  }
}

async function waitForSave(page: import('@playwright/test').Page) {
  await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved', {
    timeout: 15_000,
  });
}

test.describe('image board', () => {
  test('renders floating cells over the picture', async ({ page }) => {
    await createImageAndOpen(page, uniqueName('Image Render'));

    await expect(page.locator('#canvas-grid')).toHaveCount(0);
    await expect(page.locator('#canvas-bento')).toHaveCount(0);

    const picture = page.locator('#image-board img');
    await expect(picture).toHaveAttribute('src', '/images/image-board-blueprint.svg');

    // The card keeps the canvas cell body and the Markdown field.
    await expect(page.locator('#image-cell-brief')).toBeVisible();
    await expect(page.locator('#cell-card-brief')).toBeVisible();
    await expect(page.locator('#md-brief-content')).toBeVisible();

    // A text cell is one input, not a card.
    await expect(page.locator('#text-cell-next_step')).toHaveValue('Next step');
    await expect(page.locator('#cell-card-next_step')).toHaveCount(0);

    // The brief sits inside the picture, at a quarter of its width.
    const boardBox = (await page.locator('#image-board').boundingBox())!;
    const briefBox = (await page.locator('#image-cell-brief').boundingBox())!;

    expect(briefBox.x).toBeGreaterThanOrEqual(boardBox.x);
    expect(briefBox.x + briefBox.width).toBeLessThanOrEqual(boardBox.x + boardBox.width + 1);
    expect(briefBox.width / boardBox.width).toBeCloseTo(0.28, 1);

    await expect(page.locator('#image-size')).toContainText('3 cells');
  });

  test('edits a text label and survives a reload', async ({ page }) => {
    const text = `Exit ${Date.now()}`;
    await createImageAndOpen(page, uniqueName('Image Text'));

    const input = page.locator('#text-cell-next_step');
    await input.fill(text);
    await input.blur();

    await waitForSave(page);
    await page.reload({ waitUntil: 'networkidle' });

    await expect(page.locator('#text-cell-next_step')).toHaveValue(text);
  });

  test('moves and resizes a cell with the keyboard', async ({ page }) => {
    await createImageAndOpen(page, uniqueName('Image Keyboard'));

    await page.locator('#edit-layout-toggle').click();

    const cell = page.locator('#image-cell-brief');
    await expect(cell).toHaveAttribute('style', /left: 4%; top: 8%/);

    // Half a percent right: one step, not a whole percent.
    await page.locator('#image-move-brief').focus();
    await page.keyboard.press('ArrowRight');
    await expect(cell).toHaveAttribute('style', /left: 4.5%/);

    // Shift + arrow grows the cell by the same half step.
    await page.locator('#image-move-brief').focus();
    await page.keyboard.press('Shift+ArrowDown');
    await expect(cell).toHaveAttribute('style', /height: 18.5%/);

    await waitForSave(page);
    await page.reload({ waitUntil: 'networkidle' });

    await expect(page.locator('#image-cell-brief')).toHaveAttribute('style', /left: 4.5%/);
    await expect(page.locator('#image-cell-brief')).toHaveAttribute('style', /height: 18.5%/);
  });

  test('dragging the corner resizes by percentage', async ({ page }) => {
    await createImageAndOpen(page, uniqueName('Image Drag Resize'));

    await page.locator('#edit-layout-toggle').click();

    const cell = page.locator('#image-cell-brief');
    const handle = page.locator('#image-resize-brief');
    const boardBox = (await page.locator('#image-board').boundingBox())!;

    await expect(cell).toHaveAttribute('style', /width: 28%/);

    const handleBox = (await handle.boundingBox())!;
    await page.mouse.move(handleBox.x + handleBox.width / 2, handleBox.y + handleBox.height / 2);
    await page.mouse.down();
    // Two percent of the picture to the right: half-percent snapping keeps it.
    await page.mouse.move(
      handleBox.x + handleBox.width / 2 + boardBox.width * 0.02,
      handleBox.y + handleBox.height / 2,
      { steps: 6 },
    );
    await page.mouse.up();

    await waitForSave(page);
    await page.reload({ waitUntil: 'networkidle' });

    await expect(page.locator('#image-cell-brief')).toHaveAttribute('style', /width: 30%/);
  });

  test('changes the backdrop and pins the board shape', async ({ page }) => {
    await createImageAndOpen(page, uniqueName('Image Backdrop'));

    await page.locator('#edit-layout-toggle').click();

    const url = page.locator('#image-backdrop-url');
    await expect(url).toHaveValue('/images/image-board-blueprint.svg');

    await url.fill('/images/favicon.svg');
    await url.blur();

    await expect(page.locator('#image-board img')).toHaveAttribute('src', '/images/favicon.svg');
    await waitForSave(page);

    // A pinned shape gives the board a stable frame while the picture fits.
    await page.locator('#image-backdrop-aspect').selectOption('16:9');
    await expect(page.locator('#image-board')).toHaveAttribute('style', /aspect-ratio: 1.7778/);

    await waitForSave(page);
    await page.reload({ waitUntil: 'networkidle' });

    await expect(page.locator('#image-board img')).toHaveAttribute('src', '/images/favicon.svg');
    await expect(page.locator('#image-board')).toHaveAttribute('style', /aspect-ratio: 1.7778/);
  });

  test('adds a card and a text cell to the picture', async ({ page }) => {
    await createImageAndOpen(page, uniqueName('Image Add'));

    await page.locator('#edit-layout-toggle').click();
    await page.locator('#add-image-cell').click();
    await expect(page.locator('#image-cell-cell1')).toBeVisible();
    await expect(page.locator('#cell-card-cell1')).toBeVisible();

    await page.locator('#add-image-text').click();
    await expect(page.locator('#image-cell-text1')).toBeVisible();
    await expect(page.locator('#text-cell-text1')).toBeVisible();

    await expect(page.locator('#image-size')).toContainText('5 cells');

    await waitForSave(page);
    await page.reload({ waitUntil: 'networkidle' });

    await expect(page.locator('#image-cell-cell1')).toBeVisible();
    await expect(page.locator('#image-cell-text1')).toBeVisible();
  });
});
