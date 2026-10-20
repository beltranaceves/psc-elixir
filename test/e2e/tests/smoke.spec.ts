import { test, expect } from '@playwright/test';

// Smoke tests: prove the authenticated app shell loads for the main areas.
// These run with the storageState from tests/auth.setup.ts (logged in as e2e user).
//
// Index page titles live in the app header so they do not repeat the page's
// navigation context in the main body.

test.describe('authenticated app', () => {
  test('documents index loads', async ({ page }) => {
    await page.goto('/documents');
    await expect(page).toHaveURL(/\/documents/);
    await expect(page.getByRole('heading', { level: 1, name: 'My Documents' })).toBeVisible();
  });

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
    // The primary action lives in the app header, next to the page title.
    await expect(page.locator('header #new-template-button')).toBeVisible();
  });

  test('the New Template action adapts to the available room', async ({ page }) => {
    // Phones get the plus icon only, so the route title keeps its space.
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/templates');
    const button = page.locator('header #new-template-button');
    await expect(button).toBeVisible();
    await expect(button.getByText('New Template')).toBeHidden();

    // With room, the action states what it does.
    await page.setViewportSize({ width: 1280, height: 844 });
    await expect(button.getByText('New Template')).toBeVisible();
    await expect(button).toHaveText('New Template');
  });
});
