import { test, expect, type Page } from '@playwright/test';

// The admin surface is Backpex behind a role guard. These tests run with the
// storage state from tests/auth.setup.ts (e2e@example.com, promoted to admin
// by priv/repo/e2e_seeds.exs).
const USER_B = 'e2e2@example.com';
const PASSWORD_B = 'e2e2-password-123';

async function logInAsB(page: Page) {
  await page.goto('/users/log-in');
  await page.locator('.phx-connected').first().waitFor();

  const form = page.locator('#login_form_password');
  await form.locator('input[name="user[email]"]').fill(USER_B);
  await form.locator('input[name="user[password]"]').fill(PASSWORD_B);
  await form.getByRole('button', { name: 'Log in', exact: true }).click();
  await expect(page.getByRole('link', { name: 'Log out' })).toBeVisible();
}

test.describe('administration', () => {
  test('the dashboard and every resource page load for an admin', async ({ page }) => {
    await page.goto('/admin');
    await expect(page).toHaveURL(/\/admin$/);
    await expect(page.getByRole('heading', { name: 'Administration' })).toBeVisible();
    await expect(page.locator('#backpex-app-shell')).toBeVisible();

    // The four resource cards navigate into Backpex.
    for (const path of ['/admin/users', '/admin/templates', '/admin/canvases', '/admin/notes']) {
      await expect(page.locator(`a[href="${path}"]`).first()).toBeVisible();
    }

    await page.locator('a[href="/admin/users"]').first().click();
    await expect(page).toHaveURL(/\/admin\/users/);
    await expect(page.locator('#backpex-app-shell')).toBeVisible();
    await expect(page.getByText('e2e@example.com').first()).toBeVisible();

    await page.goto('/admin/templates');
    // The seeded built-in defaults are listed.
    await expect(page.getByText('Problem–Solution Canvas').first()).toBeVisible();
    await expect(page.getByText('Scratchpad').first()).toBeVisible();

    await page.goto('/admin/canvases');
    await expect(page.locator('#backpex-app-shell')).toBeVisible();

    await page.goto('/admin/notes');
    await expect(page.locator('#backpex-app-shell')).toBeVisible();
  });

  test('a member is redirected back to the app', async ({ browser, baseURL }) => {
    // Explicit empty storage state: the project's storageState (user A) leaks
    // into manually created contexts in this Playwright version.
    const context = await browser.newContext({
      baseURL,
      storageState: { cookies: [], origins: [] },
    });
    const page = await context.newPage();

    await logInAsB(page);
    await page.goto('/admin/users');

    await expect(page).toHaveURL(/\/canvas$/);
    await expect(page.getByRole('heading', { name: 'Administration' })).toHaveCount(0);

    await context.close();
  });

  test('an admin sees the Admin nav entry and a member does not', async ({ page, browser, baseURL }) => {
    await page.goto('/canvas');
    await expect(page.locator('header a[href="/admin"]').first()).toBeVisible();

    const context = await browser.newContext({
      baseURL,
      storageState: { cookies: [], origins: [] },
    });
    const memberPage = await context.newPage();
    await logInAsB(memberPage);
    await memberPage.goto('/canvas');
    await expect(memberPage.locator('header a[href="/admin"]')).toHaveCount(0);

    await context.close();
  });
});
