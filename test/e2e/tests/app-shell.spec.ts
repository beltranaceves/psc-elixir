import { test, expect } from '@playwright/test';

/**
 * App shell E2E tests (header, menus).
 *
 * The theme switch lives in the hamburger menu below `xl`. Its sliding thumb
 * used to sit on top of the segment of the current theme and swallow the
 * click, so picking the theme you were already on did nothing.
 */

test.describe('app shell', () => {
  test('the shell is sized with the dynamic viewport', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();

    // `min-h-screen` is 100vh: the *large* viewport, which on a phone is
    // taller than the app (sized in dvh) by the height of the browser
    // toolbar. The page then scrolls vertically and shows an empty strip
    // under the app. The body must follow the dynamic viewport instead.
    await expect(page.locator('body')).toHaveClass(/min-h-dvh/);
    await expect(page.locator('body')).not.toHaveClass(/min-h-screen|h-screen/);
  });

  test('the theme picker in the menu can pick the theme that is already on', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();

    await page.locator('header details[data-menu] summary').click();

    const theme = await page.evaluate(
      () => document.documentElement.getAttribute('data-theme') || 'system',
    );
    const label = `${theme.charAt(0).toUpperCase()}${theme.slice(1)} theme`;

    // Clicking the segment of the current theme must still register.
    await page.locator(`header details[data-menu] button[aria-label="${label}"]`).click();
    await expect(
      page.locator('header details[data-menu] button[aria-label="Light theme"]'),
    ).toBeVisible();
    expect(
      await page.evaluate(() => document.documentElement.getAttribute('data-theme') || 'system'),
    ).toBe(theme);

    // The other segments still switch the theme.
    await page.locator('header details[data-menu] button[aria-label="Dark theme"]').click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    await page.locator('header details[data-menu] button[aria-label="Light theme"]').click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  });
});
