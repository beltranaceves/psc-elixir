import { test, expect } from '@playwright/test';

// Smoke tests: prove the authenticated app shell loads for the main areas.
// These run with the storageState from auth.setup.ts (logged in as e2e user).

test.describe('authenticated app', () => {
  test('documents index loads', async ({ page }) => {
    await page.goto('/documents');
    await expect(page).toHaveURL(/\/documents/);
    await expect(page.getByRole('heading', { name: 'My Documents' })).toBeVisible();
  });

  test('canvases index loads', async ({ page }) => {
    await page.goto('/canvases');
    await expect(page).toHaveURL(/\/canvases/);
    await expect(page.getByRole('heading', { name: 'Canvases' })).toBeVisible();
  });

  test('canvas layouts index loads', async ({ page }) => {
    await page.goto('/canvas-layouts');
    await expect(page).toHaveURL(/\/canvas-layouts/);
    await expect(page.getByRole('heading', { name: 'Canvas Layouts' })).toBeVisible();
  });
});