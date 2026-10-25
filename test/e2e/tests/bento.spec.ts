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

    // The board reports its real grid, in columns × rows.
    await expect(page.locator('#bento-size')).toContainText('12 × 5');

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

    // Each card shows its own width × height while arranging.
    await expect(page.locator('#bento-size-decision')).toHaveText('6 × 2');

    const card = page.locator('#bento-card-card1');
    const before = await card.boundingBox();

    // The move grip takes arrow keys: one column left, then shift+down grows.
    await page.locator('#bento-move-card1').focus();
    await page.keyboard.press('ArrowRight');
    // Half a column: track 2 of 24, not track 3.
    await expect(card).toHaveCSS('grid-column-start', '2');

    await page.locator('#bento-move-card1').focus();
    await page.keyboard.press('Shift+ArrowDown');

    await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved', {
      timeout: 15_000,
    });

    // Resize moves in half rows: the card's grid row span grows from 4 to 5
    // tracks. Its pixel height follows the placement, but never below the
    // content, which is the point of `h` being a minimum.
    await expect(card).toHaveAttribute('style', /grid-row: 11 \/ span 5/);

    const after = await card.boundingBox();
    expect(after).not.toBeNull();
    expect(before).not.toBeNull();
    expect(after!.height).toBeGreaterThanOrEqual(before!.height);
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

  test('edits the board grid from the toolbar', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Grid'));

    await expect(page.locator('#bento-columns-input')).toHaveCount(0);
    await page.locator('#edit-layout-toggle').click();

    // Columns: type a number, and the board reflows to it.
    await page.locator('#bento-columns-input').fill('8');
    await expect(page.locator('#bento-board')).toHaveAttribute(
      'style',
      /--bento-columns: 8;/,
      { timeout: 10_000 },
    );

    // Rows: the container reserves the space even where no card reaches.
    await page.locator('#bento-rows-input').fill('9');
    await expect(page.locator('#bento-board')).toHaveCSS('min-height', '712px', {
      timeout: 10_000,
    });

    await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved', {
      timeout: 15_000,
    });

    // Reading mode shows the same grid as a badge, and it survives a reload.
    await page.locator('#edit-layout-toggle').click();
    await expect(page.locator('#bento-size')).toContainText('8 × 9');

    await page.reload({ waitUntil: 'networkidle' });
    await expect(page.locator('#bento-size')).toContainText('8 × 9');
    await expect(page.locator('#bento-board')).toHaveCSS('min-height', '712px');
  });

  test('a tall board scrolls the page on a desktop, not itself', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Tall'));

    await page.locator('#edit-layout-toggle').click();
    await page.locator('#bento-rows-input').fill('14');
    await expect(page.locator('#bento-board')).toHaveCSS('min-height', '1112px', {
      timeout: 10_000,
    });

    await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved', {
      timeout: 15_000,
    });

    // The board is not its own scroll box on a wide screen: the page is.
    await expect(page.locator('.canvas-bento-scroll')).toHaveCSS('overflow-y', 'visible');

    const metrics = await page.evaluate(() => {
      const main = document.querySelector('main')!;
      const board = document.querySelector('.canvas-bento-scroll')!;
      return {
        mainScroll: main.scrollHeight,
        mainClient: main.clientHeight,
        boardScroll: board.scrollHeight,
        boardClient: board.clientHeight,
      };
    });

    expect(metrics.boardScroll - metrics.boardClient).toBeLessThanOrEqual(2);
    expect(metrics.mainScroll).toBeGreaterThan(metrics.mainClient + 100);
  });

  test('dragging a card moves it in half columns', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Half Move'));

    await page.locator('#edit-layout-toggle').click();

    const board = page.locator('#bento-board');
    const unit = (await board.boundingBox())!.width / 12;
    const card = page.locator('#bento-card-decision');
    const gripBox = (await page.locator('#bento-move-decision').boundingBox())!;

    // Half a column of travel is a half-unit placement, the same step a
    // resize uses: track 2 rather than track 3.
    await page.mouse.move(gripBox.x + gripBox.width / 2, gripBox.y + gripBox.height / 2);
    await page.mouse.down();
    await page.mouse.move(
      gripBox.x + gripBox.width / 2 + unit / 2,
      gripBox.y + gripBox.height / 2,
      { steps: 6 },
    );
    await page.mouse.up();

    await expect(card).toHaveCSS('grid-column-start', '2', { timeout: 10_000 });
  });

  test('widening the board opens room to drag a card into it', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Widen'));

    await page.locator('#edit-layout-toggle').click();
    await page.locator('#bento-columns-input').fill('16');
    await expect(page.locator('#bento-board')).toHaveAttribute(
      'style',
      /--bento-columns: 16;/,
      { timeout: 10_000 },
    );

    const card = page.locator('#bento-card-decision');
    const grip = page.locator('#bento-move-decision');
    const board = page.locator('#bento-board');

    // The grid is read from the DOM at the start of a drag, so the new width
    // is usable without a reload.
    const unit = (await board.boundingBox())!.width / 16;
    const gripBox = (await grip.boundingBox())!;

    await page.mouse.move(gripBox.x + gripBox.width / 2, gripBox.y + gripBox.height / 2);
    await page.mouse.down();
    await page.mouse.move(
      gripBox.x + gripBox.width / 2 + unit * 8,
      gripBox.y + gripBox.height / 2,
      { steps: 10 },
    );
    await page.mouse.up();

    // x = 8 → the ninth column → track 17.
    await expect(card).toHaveAttribute('style', /grid-column: 17 \//);
    await expect(page.locator('#bento-columns-input')).toHaveValue('16');
  });

  test('dragging a card past the right edge widens the board', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Grow'));

    await page.locator('#edit-layout-toggle').click();

    const board = page.locator('#bento-board');
    const unit = (await board.boundingBox())!.width / 12;
    const gripBox = (await page.locator('#bento-move-evidence').boundingBox())!;

    // evidence sits at x=8, 4 wide, on a 12-column board: one column right
    // needs 13 and grows the board with it.
    await page.mouse.move(gripBox.x + gripBox.width / 2, gripBox.y + gripBox.height / 2);
    await page.mouse.down();
    await page.mouse.move(
      gripBox.x + gripBox.width / 2 + unit,
      gripBox.y + gripBox.height / 2,
      { steps: 8 },
    );
    await page.mouse.up();

    await expect(board).toHaveAttribute('style', /--bento-columns: 13;/, { timeout: 10_000 });
    await expect(page.locator('#bento-columns-input')).toHaveValue('13');
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

  test('a tall board keeps its own scroll area on a phone', async ({ page }) => {
    await createBentoAndOpen(page, uniqueName('Bento Tall Phone'));

    await page.locator('#edit-layout-toggle').click();
    await page.locator('#bento-rows-input').fill('14');
    await expect(page.locator('#bento-board')).toHaveCSS('min-height', '1112px', {
      timeout: 10_000,
    });

    // On a phone the board keeps its inner scroll: the page shell itself does
    // not scroll.
    await expect(page.locator('.canvas-bento-scroll')).toHaveCSS('overflow-y', 'auto');

    const metrics = await page.evaluate(() => {
      const main = document.querySelector('main')!;
      const board = document.querySelector('.canvas-bento-scroll')!;
      return { mainOverflow: main.scrollHeight - main.clientHeight, boardOverflow: board.scrollHeight - board.clientHeight };
    });

    expect(metrics.boardOverflow).toBeGreaterThan(100);
    expect(metrics.mainOverflow).toBeLessThanOrEqual(2);
  });
});
