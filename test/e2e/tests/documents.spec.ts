import { test, expect } from '@playwright/test';

function uniqueName(label: string): string {
  return `${label} ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

test.describe('document editor', () => {
  test('switches between raw Markdown and inline preview on focus', async ({ page }) => {
    const title = uniqueName('Markdown document');

    await page.goto('/documents');
    await page.locator('.phx-connected').first().waitFor();
    await page.getByRole('button', { name: 'New Document' }).click();

    const form = page.locator('#new-document-form');
    await expect(form.locator('#new-document-title')).toBeVisible();
    await form.locator('#new-document-title').fill(title);
    await form.getByRole('button', { name: 'Create' }).click();

    const documentCard = page.locator('a').filter({ hasText: title }).first();
    await expect(documentCard).toBeVisible();
    await documentCard.click();
    await page.waitForURL(/\/documents\/\d+/);

    const editor = page.locator('#editor');
    const preview = page.locator('#document-markdown-preview');

    await expect(editor).toBeHidden();
    await expect(preview).toBeVisible();

    await preview.click();
    await expect(editor).toBeVisible();
    await expect(preview).toBeHidden();

    await editor.fill('# Meeting notes\n\n**Ready**');
    await editor.blur();

    await expect(preview).toBeVisible();
    await expect(editor).toBeHidden();
    await expect(preview.locator('h1')).toHaveText('Meeting notes');
    await expect(preview.locator('strong')).toHaveText('Ready');
  });
});
