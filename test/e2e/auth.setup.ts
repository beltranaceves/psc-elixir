import { test as setup, expect } from '@playwright/test';

const AUTH_FILE = '.auth/user.json';

setup('authenticate as e2e user', async ({ page }) => {
  await page.goto('/users/log-in');

  // The login page has two forms (magic link + password); scope to the
  // password form by its DOM id.
  const passwordForm = page.locator('#login_form_password');
  await passwordForm.getByLabel('Email').fill('e2e@example.com');
  await passwordForm.getByLabel('Password').fill('e2e-password-123');
  await passwordForm.getByRole('button', { name: 'Log in and stay logged in' }).click();

  // Post-login redirect is /users/settings (see UserAuth.signed_in_path/1).
  await expect(page).toHaveURL(/\/users\/settings/);

  await page.context().storageState({ path: AUTH_FILE });
});