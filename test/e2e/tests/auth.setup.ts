import { test as setup, expect } from '@playwright/test';

const AUTH_FILE = '.auth/user.json';
const EMAIL = 'e2e@example.com';
const PASSWORD = 'e2e-password-123';

/**
 * Logs in once through the real UI and saves the session for the other tests.
 *
 * Two LiveView-specific details matter here:
 *
 * 1. The login form is a LiveView form (`phx-submit` + `phx-trigger-action`).
 *    Values typed before the view finishes connecting can be wiped when the
 *    first server diff is applied, so we wait for `.phx-connected` first.
 * 2. The page has two forms (magic link + password) that both contain an
 *    "Email" field, so we scope to the password form and address inputs by
 *    name rather than by label.
 *
 * The seeded user is pre-confirmed so the email-confirmation flow is skipped.
 */
setup('authenticate as e2e user', async ({ page }) => {
  await page.goto('/users/log-in');
  await page.locator('.phx-connected').first().waitFor();

  const passwordForm = page.locator('#login_form_password');
  const emailInput = passwordForm.locator('input[name="user[email]"]');
  const passwordInput = passwordForm.locator('input[name="user[password]"]');

  await emailInput.fill(EMAIL);
  await passwordInput.fill(PASSWORD);

  // Fail loudly here rather than after the submit if the values were clobbered.
  await expect(emailInput).toHaveValue(EMAIL);
  await expect(passwordInput).toHaveValue(PASSWORD);

  await passwordForm.getByRole('button', { name: 'Log in and stay logged in' }).click();

  // A fresh login lands on "/" — `UserAuth.signed_in_path/1` only redirects to
  // /users/settings when `current_scope` is already assigned (i.e. when an
  // already-authenticated user re-authenticates). Assert on authenticated
  // state instead of a specific landing URL.
  await expect(page.getByRole('link', { name: 'Log out' })).toBeVisible();

  await page.context().storageState({ path: AUTH_FILE });
});