import { test, expect } from '@playwright/test';

// Smoke tests: prove the authenticated app shell loads for the main areas.
// These run with the storageState from tests/auth.setup.ts (logged in as e2e user).
//
// Index page titles live in the app header so they do not repeat the page's
// navigation context in the main body.

function uniqueName(label: string): string {
  return `${label} ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

test.describe('authenticated app', () => {
  test('canvases index loads', async ({ page }) => {
    await page.goto('/canvas');
    await expect(page).toHaveURL(/\/canvas/);
    await expect(page.locator('#header-page-title')).toHaveText('Canvases');
    await expect(page.locator('main h1')).toHaveCount(0);
  });

  test('templates index loads', async ({ page }) => {
    await page.goto('/templates');
    await expect(page).toHaveURL(/\/templates/);
    await expect(page.locator('#header-page-title')).toHaveText('Templates');
    await expect(page.locator('main h1')).toHaveCount(0);
    // The create action is the first tile of the library, not a header button.
    await expect(page.locator('#new-template-card')).toBeVisible();
    // The catalog is the second tile, right after it.
    await expect(page.locator('#catalog-card')).toBeVisible();
    await expect(page.locator('#catalog-card')).toHaveAttribute('href', '/catalog');
  });

  test('the New Template card leads the library at the same size as a template', async ({
    page,
  }) => {
    await page.goto('/templates');
    await page.locator('.phx-connected').first().waitFor();

    // Nothing in the header competes with the page title.
    await expect(page.locator('header a[href="/templates/new"]')).toHaveCount(0);

    // The card is the first tile of the grid.
    const grid = page.locator('#template-grid');
    await expect(grid.locator('> *').first()).toHaveAttribute('id', 'new-template-card');

    // Create a template so the two tiles can be compared.
    await page.goto('/templates/new');
    await page.locator('.phx-connected').first().waitFor();
    // A template needs at least one row and one column to be valid.
    await page.getByRole('button', { name: 'Add Column' }).click();
    await page.getByRole('button', { name: 'Add Row' }).click();
    await page.locator('#template-form input[name="name"]').fill(uniqueName('Grid Tile'));
    await page.getByRole('button', { name: 'Save Template' }).click();
    await page.waitForURL(/\/templates$/);

    const createBox = await page.locator('#new-template-card').boundingBox();
    const templateBox = await page.locator('[id^="template-card-"]').first().boundingBox();
    expect(createBox).not.toBeNull();
    expect(templateBox).not.toBeNull();
    expect(Math.abs(createBox!.width - templateBox!.width)).toBeLessThan(1);
    expect(Math.abs(createBox!.height - templateBox!.height)).toBeLessThan(1);
  });
});
