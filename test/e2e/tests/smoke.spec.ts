import { test, expect } from '@playwright/test';

// Smoke tests: prove the authenticated app shell loads for the main areas.
// These run with the storageState from tests/auth.setup.ts (logged in as e2e user).
//
// Assert on the page's level-1 heading, which is the page title. Matching by
// role+level keeps the selectors precise: a loose name match for "Canvases"
// would also resolve the "My Canvases" heading, causing a strict-mode violation.

test.describe('authenticated app', () => {
  test('documents index loads', async ({ page }) => {
    await page.goto('/documents');
    await expect(page).toHaveURL(/\/documents/);
    await expect(page.getByRole('heading', { level: 1, name: 'My Documents' })).toBeVisible();
  });

  test('canvases index loads', async ({ page }) => {
    await page.goto('/canvases');
    await expect(page).toHaveURL(/\/canvases/);
    await expect(page.getByRole('heading', { level: 1, name: 'Canvases' })).toBeVisible();
  });

  test('canvas layouts index loads', async ({ page }) => {
    await page.goto('/canvas-layouts');
    await expect(page).toHaveURL(/\/canvas-layouts/);
    await expect(page.getByRole('heading', { level: 1, name: 'Canvas Layouts' })).toBeVisible();
  });
});