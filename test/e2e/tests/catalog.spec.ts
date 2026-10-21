import { test, expect } from '@playwright/test';

/**
 * The catalog: the public face of the template library.
 *
 * A template its owner marked public is listed at /catalog, ranked by how many
 * times it has been used. A card opens a modal with the details and a picture
 * of the grid, and offers Use template and Fork.
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

// Publishes a fresh template and leaves the designer. Every test creates its
// own, because the tests run in parallel against one catalog.
async function publishTemplate(page: import('@playwright/test').Page, name: string) {
  await page.goto('/templates/new');
  await page.locator('.phx-connected').first().waitFor();

  await page.getByRole('button', { name: 'Add Column' }).click();
  await page.getByRole('button', { name: 'Add Column' }).click();
  await page.getByRole('button', { name: 'Add Row' }).click();
  await page.getByRole('button', { name: 'Add Row' }).click();
  await page.locator('#template-public').check();
  await page.locator('#template-form input[name="name"]').fill(name);
  await page.getByRole('button', { name: 'Save Template' }).click();
  await page.waitForURL(/\/templates$/);
}

async function openCard(page: import('@playwright/test').Page, name: string) {
  await page.goto('/catalog');
  await page.locator('.phx-connected').first().waitFor();

  const card = page.getByRole('button', { name: `Details for ${name}` });
  await expect(card).toBeVisible();
  await card.click();

  // The dialog's root is a zero-size anchor; the panel is what is on screen.
  const dialog = page.locator('#catalog-template-dialog [data-part="content-panel"]');
  await expect(dialog).toBeVisible();
  return dialog;
}

test.describe('catalog', () => {
  test('a published template is listed, searchable and inspectable', async ({ page }) => {
    const name = uniqueName('Catalogued');
    await publishTemplate(page, name);

    const dialog = await openCard(page, name);
    await expect(dialog).toContainText('2 rows × 2 columns');
    // The grid preview is a picture of the template, not its editor: a cell
    // with no label shows its key.
    await expect(dialog).toContainText('r1_c1');
    await dialog.getByRole('button', { name: 'Close dialog' }).click();
    await expect(dialog).toBeHidden();
  });

  test('the catalog leads the template picker', async ({ page, context }) => {
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();

    // The catalog is a link, not a choice: it has no aria-pressed, and it
    // opens in a new tab so a name already typed is not lost.
    const catalog = page.locator('#template-picker-catalog');
    await expect(catalog).toBeVisible();
    await expect(catalog).toHaveAttribute('href', '/catalog');
    await expect(catalog).toHaveAttribute('target', '_blank');
    expect(await catalog.getAttribute('aria-pressed')).toBeNull();

    // It is the first card in the row.
    const first = page.locator('#template-picker > *').first();
    await expect(first).toHaveAttribute('id', 'template-picker-catalog');

    // Clicking it opens the catalog in a new tab, and the draft name survives
    // in the tab it came from.
    await page.getByPlaceholder('Enter canvas name...').fill('Draft name');

    const [popup] = await Promise.all([
      context.waitForEvent('page'),
      catalog.click(),
    ]);

    await popup.waitForLoadState('domcontentloaded');
    await expect(popup).toHaveURL(/\/catalog$/);
    expect(await page.getByPlaceholder('Enter canvas name...').inputValue()).toBe('Draft name');
  });

  test('search narrows the catalog', async ({ page }) => {
    const name = uniqueName('Searchable');
    await publishTemplate(page, name);

    await page.goto('/catalog');
    await page.locator('.phx-connected').first().waitFor();

    await page.getByLabel('Search templates').fill(name.slice(0, 14));
    await expect(page.getByRole('button', { name: `Details for ${name}` })).toBeVisible();

    await page.getByLabel('Search templates').fill('no such template exists here');
    await expect(page.locator('#catalog-empty-state')).toBeVisible();
  });

  test('using a template creates a canvas and counts the use', async ({ page }) => {
    const name = uniqueName('Used');
    await publishTemplate(page, name);

    const dialog = await openCard(page, name);
    await dialog.getByRole('button', { name: 'Use template' }).click();
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);

    // The count on the card is durable proof the use was recorded.
    await page.goto('/catalog');
    await page.locator('.phx-connected').first().waitFor();
    await expect(page.getByRole('button', { name: `Details for ${name}` })).toContainText(
      'Used 1',
    );
  });

  test('forking a template opens a copy in the designer', async ({ page }) => {
    const name = uniqueName('Forked');
    await publishTemplate(page, name);

    const dialog = await openCard(page, name);
    await dialog.getByRole('button', { name: 'Fork' }).click();
    await page.waitForURL(/\/templates\/[0-9a-f-]{36}/);
    await dismissFlash(page);

    await expect(page.locator('#template-form input[name="name"]')).toHaveValue(
      new RegExp(`^${name} \\(fork\\)$`),
    );
    // The copy carries the source's grid.
    await expect(page.locator('#template-grid')).toContainText('2 columns × 2 rows');
  });

  test('unpublishing removes a template from the catalog but keeps its canvas', async ({
    page,
  }) => {
    const name = uniqueName('Retracted');
    await publishTemplate(page, name);

    // Use it first, so the canvas exists before the template leaves.
    const dialog = await openCard(page, name);
    await dialog.getByRole('button', { name: 'Use template' }).click();
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    const canvasUrl = page.url();

    await page.goto('/templates');
    await page.locator('.phx-connected').first().waitFor();
    const card = page
      .getByRole('heading', { name })
      .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
    await card.getByRole('link', { name: 'Edit' }).click();
    await page.waitForURL(/\/templates\/[0-9a-f-]{36}/);
    await page.locator('#template-public').uncheck();
    await page.getByRole('button', { name: 'Save Template' }).click();
    await page.waitForURL(/\/templates$/);

    await page.goto('/catalog');
    await page.locator('.phx-connected').first().waitFor();
    await expect(page.getByRole('button', { name: `Details for ${name}` })).toHaveCount(0);

    // The canvas made from it is a copy and keeps working.
    await page.goto(canvasUrl);
    await expect(page.locator('#canvas-name-form')).toBeVisible();
  });
});
