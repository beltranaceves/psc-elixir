import { test, expect, type Page } from '@playwright/test';

/**
 * Unstructured canvas editor (/canvas-designer) E2E tests.
 *
 * test 1 — single-player: create a canvas, edit a cell through the
 *   MarkdownField hook (click → type → blur), watch the autosave badge go
 *   Unsaved → Saved, then reload to prove the CRDT snapshot/event replay
 *   persisted the edit server-side.
 *
 * test 2 — multiplayer CRDT: two browser contexts, two users (the seeded
 *   e2e user via storageState + a second seeded account logged in through
 *   the UI on a fresh context). The owner shares the canvas, both users
 *   appear in Phoenix Presence ("Active Users"), and cell edits made by one
 *   user propagate to the other user's DOM in real time via the PubSub
 *   broadcast → cell_updated push → render_field roundtrip — with no
 *   reload. A final reload proves both edits were persisted.
 *
 * Seeded accounts come from priv/repo/e2e_seeds.exs (run by global-setup).
 */

const USER_A = 'e2e@example.com';
const USER_B = 'e2e2@example.com';
const PASSWORD_B = 'e2e2-password-123';

function uniqueName(label: string): string {
  return `${label} ${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

async function dismissFlash(page: Page): Promise<void> {
  const close = page.locator('#flash-group').getByRole('button', { name: 'close' }).first();
  if (await close.isVisible().catch(() => false)) {
    await close.click();
    await expect(close).toBeHidden();
  }
}

/** Create a canvas from the index page and open its editor. */
async function createCanvasAndOpen(page: Page, name: string): Promise<string> {
  await page.goto('/canvas-designer');
  await page.locator('.phx-connected').first().waitFor();

  await page.getByPlaceholder('Enter canvas name...').fill(name);
  await page.getByRole('button', { name: 'Create Canvas' }).click();

  await expect(page.locator('#flash-group')).toContainText('Canvas created successfully');
  await dismissFlash(page);

  // h3 is a direct child of the card div that owns the Edit link.
  const card = page.locator(`h3:text-is("${name}")`).locator('..');
  await card.getByRole('link', { name: 'Edit' }).click();

  await page.waitForURL(/\/canvas-designer\/[0-9a-f-]{36}/);
  await expect(page.locator('#canvas-name-form')).toBeVisible();
  return page.url();
}

/**
 * Edit the `content` field of a cell through the MarkdownField hook.
 * `initialText` is what the display should currently show — the fresh-cell
 * placeholder by default, or a previously synced value when overwriting a
 * cell another user already edited. Waiting on it proves the hook is
 * mounted (its initial/synced render_field roundtrip completed), so the
 * click is guaranteed to be handled.
 */
async function editCell(page: Page, cellKey: string, text: string, initialText = 'Click to edit') {
  const display = page.locator(`#md-render-${cellKey}-content`);
  await expect(display).toContainText(initialText, { timeout: 15_000 });

  await display.click();
  const textarea = page.locator(`#md-${cellKey}-content textarea`);
  await textarea.fill(text);
  await textarea.blur();

  // The blur handler requests a server-side Markdown re-render.
  await expect(display).toContainText(text, { timeout: 15_000 });
}

test.describe('canvas editor (single player)', () => {
  test('creates a canvas, edits a cell, autosaves and persists across reload', async ({
    page,
  }) => {
    const canvasName = uniqueName('Persistence Canvas');
    const editText = `single-player content ${Date.now()}`;

    await createCanvasAndOpen(page, canvasName);
    await expect(page.locator('#canvas-name-form input')).toHaveValue(canvasName);

    // Inline edit flow (not editCell) so we can catch the short-lived
    // "Unsaved" badge between the first op and the 1.5s idle save.
    const display = page.locator('#md-render-problem-content');
    await expect(display).toContainText('Click to edit', { timeout: 15_000 });
    await display.click();

    const textarea = page.locator('#md-problem-content textarea');
    await textarea.fill(editText);
    await expect(page.locator('span:text-is("Unsaved")')).toBeVisible();

    await textarea.blur();
    await expect(display).toContainText(editText, { timeout: 15_000 });

    // Idle save fires 1.5s after the last op → badge settles on Saved.
    await expect(page.locator('span:text-is("Saved")')).toBeVisible({ timeout: 15_000 });

    // Reload: content must be rebuilt from the saved snapshot + event replay.
    await page.reload();
    await expect(page.locator('#md-render-problem-content')).toContainText(editText);
    await expect(page.locator('#canvas-name-form input')).toHaveValue(canvasName);
  });
});

test.describe('canvas editor (multiplayer CRDT)', () => {
  test('shares a canvas and syncs cell edits between two users in real time', async ({
    page,
    browser,
    baseURL,
  }) => {
    test.setTimeout(90_000);

    const canvasName = uniqueName('Collab Canvas');
    const textFromA = `hello from A ${Date.now()}`;
    const textFromB = `hello from B ${Date.now()}`;
    const textFromBOverwrite = `B overwrites ${Date.now()}`;

    // --- User A: create + share -----------------------------------------
    const canvasUrl = await createCanvasAndOpen(page, canvasName);

    await page.locator('#share-form input[name="email"]').fill(USER_B);
    await page.locator('#share-form').getByRole('button', { name: 'Share' }).click();
    await expect(page.locator('#flash-group')).toContainText(`Canvas shared with ${USER_B}`);
    await dismissFlash(page);

    // --- User B: fresh context, log in through the real UI --------------
    // Explicit empty storageState: in this Playwright version the project's
    // storageState (.auth/user.json = user A) leaked into manually created
    // contexts — pageB then rendered the login form in re-auth mode
    // (readonly email prefilled with A's address) and the fill hung.
    const contextB = await browser.newContext({
      baseURL,
      storageState: { cookies: [], origins: [] },
    });
    const pageB = await contextB.newPage();

    await pageB.goto('/users/log-in');
    await pageB.locator('.phx-connected').first().waitFor();

    const passwordForm = pageB.locator('#login_form_password');
    await passwordForm.locator('input[name="user[email]"]').fill(USER_B);
    await passwordForm.locator('input[name="user[password]"]').fill(PASSWORD_B);
    await passwordForm.getByRole('button', { name: 'Log in', exact: true }).click();
    await expect(pageB.getByRole('link', { name: 'Log out' })).toBeVisible();

    await pageB.goto(canvasUrl);
    await expect(pageB.locator('#canvas-name-form input')).toHaveValue(canvasName);

    // --- Presence: both users see each other in "Active Users" -----------
    // Badges are div.rounded-full; the shared-with list uses plain rounded.
    await expect(
      page.locator('div.rounded-full').filter({ hasText: USER_B })
    ).toBeVisible({ timeout: 15_000 });
    await expect(
      pageB.locator('div.rounded-full').filter({ hasText: USER_A })
    ).toBeVisible({ timeout: 15_000 });

    // --- A edits → B's DOM updates live (no reload) ----------------------
    await editCell(page, 'problem', textFromA);
    await expect(pageB.locator('#md-render-problem-content')).toContainText(textFromA, {
      timeout: 15_000,
    });

    // --- B edits → A's DOM updates live (bidirectional) ------------------
    await editCell(pageB, 'capabilities', textFromB);
    await expect(page.locator('#md-render-capabilities-content')).toContainText(textFromB, {
      timeout: 15_000,
    });

    // --- Same-cell conflict: B overwrites the cell A edited → both
    // converge on B's value (last-writer-wins per field) ------------------
    // B's display for this cell already shows A's synced value, not the
    // fresh-cell placeholder — pass it as the expected initial state.
    await editCell(pageB, 'problem', textFromBOverwrite, textFromA);
    await expect(page.locator('#md-render-problem-content')).toContainText(
      textFromBOverwrite,
      { timeout: 15_000 }
    );
    // A's own overwritten text must be gone from its display.
    await expect(page.locator('#md-render-problem-content')).not.toContainText(textFromA);

    // --- Both edits persisted: reload B and check CRDT state -------------
    await pageB.reload();
    await expect(pageB.locator('#md-render-problem-content')).toContainText(
      textFromBOverwrite,
      { timeout: 15_000 }
    );
    await expect(pageB.locator('#md-render-capabilities-content')).toContainText(textFromB);

    await contextB.close();
  });
});
