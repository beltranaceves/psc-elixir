import { test, expect } from '@playwright/test';

/**
 * Bento boards end to end.
 *
 * A bento is the same cells as the table canvas, arranged as cards on a fixed
 * column grid. The browser is the only place the geometry is actually laid
 * out, so these tests cover the parts the server cannot see: the CSS grid
 * placement, the drag/resize handles and the keyboard path.
 */

function uniqueName(label: string): string {
  return `${label} ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

async function createBentoAndOpen(page: import('@playwright/test').Page, name: string) {
  await page.goto('/canvas');
  await page.locator('.phx-connected').first().waitFor();

  // The built-in Bento Board is a card in the picker like any template.
  await page.getByRole('button', { name: 'Start from Bento Board' }).click();
  await page.getByPlaceholder('Enter canvas name...').fill(name);
  await page.getByRole('button', { name: 'Create Canvas' }).click();

  await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
  await expect(page.locator('#canvas-bento')).toBeVisible();
  await page.locator('.phx-connected').first().waitFor();

  const close = page.locator('#flash-group').getByRole('button', { name: 'close' }).first();
  if (await close.isVisible().catch(() => false)) {
    await close.click();
  }
}

test.describe('bento board', () => {
  test('renders cards at their placements, not a table', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Render'));

    await expect(page.locator('#canvas-grid')).toHaveCount(0);
    await expect(page.locator('#bento-card-big_picture')).toBeVisible();
    await expect(page.locator('#bento-card-evidence')).toBeVisible();

    // Two cards side by side: the big picture spans 8 of 12 columns.
    const big = page.locator('#bento-card-big_picture');
    const evidence = page.locator('#bento-card-evidence');
    const bigBox = await big.boundingBox();
    const evidenceBox = await evidence.boundingBox();

    expect(bigBox).not.toBeNull();
    expect(evidenceBox).not.toBeNull();
    expect(bigBox!.width).toBeGreaterThan(evidenceBox!.width);
    expect(evidenceBox!.x).toBeGreaterThan(bigBox!.x + bigBox!.width - 8);
  });

  test('edits a card and survives a reload', async ({ page }) => {
    const text = `bento content ${Date.now()}`;
    await createBentoAndOpen(page, uniqueName('Bento Edit'));

    const display = page.locator('#md-render-decision-content');
    await expect(display).toContainText('Click to edit', { timeout: 15_000 });
    await display.click();
    await page.locator('#md-decision-content textarea').fill(text);
    await page.locator('#md-decision-content textarea').blur();

    await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved', {
      timeout: 15_000,
    });

    await page.reload({ waitUntil: 'networkidle' });
    await expect(page.locator('#md-render-decision-content')).toContainText(text);
  });

  test('adds, moves and resizes a card with the keyboard', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Layout'));

    await expect(page.locator('#add-card-button')).toHaveCount(0);
    await page.locator('#edit-layout-toggle').click();

    await page.locator('#add-card-button').click();
    await expect(page.locator('#bento-card-card1')).toBeVisible();

    const card = page.locator('#bento-card-card1');
    const before = await card.boundingBox();

    // The move grip takes arrow keys: one column left, then shift+down grows.
    await page.locator('#bento-move-card1').focus();
    await page.keyboard.press('ArrowRight');
    await expect(card).toHaveCSS('grid-column-start', '3');

    await page.locator('#bento-move-card1').focus();
    await page.keyboard.press('Shift+ArrowDown');

    await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved', {
      timeout: 15_000,
    });

    const after = await card.boundingBox();
    expect(after).not.toBeNull();
    expect(before).not.toBeNull();

    // Resize moves in half rows: a row unit is 72px, so half a step is 40px
    // (one 32px track plus the 8px gap).
    const grown = Math.round(after!.height - before!.height);
    expect(grown).toBeGreaterThanOrEqual(38);
    expect(grown).toBeLessThanOrEqual(42);
  });

  test('dragging the corner resizes by half a column', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Drag Resize'));

    await page.locator('#edit-layout-toggle').click();

    const card = page.locator('#bento-card-decision');
    const handle = card.locator('[data-bento-resize]');
    const board = page.locator('#bento-board');

    const columns = Number(await board.getAttribute('data-columns'));
    const boardBox = (await board.boundingBox())!;
    const unit = boardBox.width / columns;

    await expect(card).toHaveCSS('grid-column-end', 'span 12');

    const handleBox = (await handle.boundingBox())!;
    await page.mouse.move(handleBox.x + handleBox.width / 2, handleBox.y + handleBox.height / 2);
    await page.mouse.down();
    await page.mouse.move(
      handleBox.x + handleBox.width / 2 + unit / 2,
      handleBox.y + handleBox.height / 2,
      { steps: 6 },
    );
    await page.mouse.up();

    // One half-column step, not a whole one.
    await expect(card).toHaveCSS('grid-column-end', 'span 13');

    await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved', {
      timeout: 15_000,
    });
  });

  test('removes an empty card straight away and confirms one with content', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Remove'));

    await page.locator('#edit-layout-toggle').click();
    await page.locator('#remove-card-evidence').click();
    await expect(page.locator('#bento-card-evidence')).toHaveCount(0);

    // A card that holds something asks first.
    const display = page.locator('#md-render-decision-content');
    await expect(display).toContainText('Click to edit', { timeout: 15_000 });
    await display.click();
    await page.locator('#md-decision-content textarea').fill('keep me');
    await page.locator('#md-decision-content textarea').blur();
    await expect(display).toContainText('keep me', { timeout: 15_000 });

    await page.locator('#remove-card-decision').click();

    // The dialog's root stays mounted; its content panel is the visible part.
    const dialog = page.locator('#remove-structure-dialog [data-part="content-panel"]');
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText('Remove this card?');

    await page.locator('#confirm-remove-structure').click();
    await expect(page.locator('#bento-card-decision')).toHaveCount(0);
  });
});

test.describe('bento board on a phone', () => {
  test.use({ viewport: { width: 390, height: 844 }, hasTouch: true });

  test('a tap fullscreens a card and a swipe follows the board', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Phone'));

    // The board keeps its spatial layout: it is wider than the viewport and
    // pans horizontally instead of squeezing twelve columns into 390px.
    const board = page.locator('#bento-board');
    const scroll = await board.evaluate(el => ({
      width: el.getBoundingClientRect().width,
      viewport: el.parentElement!.clientWidth,
    }));
    expect(scroll.width).toBeGreaterThan(scroll.viewport + 40);

    // And it actually pans: scrolling the board sideways moves it.
    const scrolled = await page.locator('.canvas-bento-scroll').evaluate(el => {
      el.scrollLeft = 240;
      return el.scrollLeft;
    });
    expect(scrolled).toBeGreaterThan(100);

    // First tap opens the card full screen; it is not editing yet.
    await page.locator('#cell-card-big_picture').tap();
    await expect(page.locator('#cell-card-big_picture')).toHaveClass(/is-expanded/);
    await expect(page.locator('#md-big_picture-content textarea')).toBeHidden();

    // Swipe left: the board's own neighbour (evidence) takes over.
    const box = await page.locator('#cell-card-big_picture').boundingBox();
    await page.mouse.move(box!.x + box!.width - 40, box!.y + box!.height / 2);
    await page.mouse.down();
    await page.mouse.move(box!.x + 40, box!.y + box!.height / 2, { steps: 8 });
    await page.mouse.up();

    await expect(page.locator('#cell-card-evidence')).toHaveClass(/is-expanded/);
  });
});
