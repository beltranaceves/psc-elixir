import { test, expect, type Browser, type Page } from '@playwright/test';

/**
 * Real-time collaboration in the Notes pane.
 *
 * The canvas's cells already sync over the CRDT event log; notes go through
 * the same machinery (`Psc.TextStore`, broadcast on `note:<id>`), so a note
 * must update in the other user's textarea without a reload. These tests are
 * the end-to-end proof: two real accounts, the owner shares the canvas
 * through the UI, and both keep the same note open.
 *
 * Two note modes are covered, because they take different paths through the
 * LiveView:
 *
 *   multi   — a canvas from the Problem–Solution template, with a note list;
 *             the note is created in the UI and its id is in the URL.
 *   single  — a scratchpad: one note, created on the server when the Notes
 *             view is opened, with no list to pick from.
 *
 * The accounts are seeded by priv/repo/e2e_seeds.exs (run by global-setup).
 * The first one is logged in by auth.setup.ts; the second is logged in here
 * in a context of its own, so the two "users" are genuinely separate
 * sessions.
 */

const USER_A = 'e2e@example.com';
const USER_B = 'e2e2@example.com';
const PASSWORD_B = 'e2e2-password-123';

const NOTE_INPUT = '#canvas-note-input';

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

/** Log the second seeded account in, in a browser context of its own. */
async function signInAsSecondUser(
  browser: Browser,
  baseURL: string | undefined,
): Promise<{ context: Awaited<ReturnType<Browser['newContext']>>; page: Page }> {
  // An explicit empty storageState: the project's default (user A) would leak
  // into a manually created context.
  const context = await browser.newContext({
    baseURL,
    storageState: { cookies: [], origins: [] },
  });
  const page = await context.newPage();

  await page.goto('/users/log-in');
  await page.locator('.phx-connected').first().waitFor();

  const passwordForm = page.locator('#login_form_password');
  await passwordForm.locator('input[name="user[email]"]').fill(USER_B);
  await passwordForm.locator('input[name="user[password]"]').fill(PASSWORD_B);
  await passwordForm.getByRole('button', { name: 'Log in', exact: true }).click();
  await expect(page.getByRole('link', { name: 'Log out' })).toBeVisible();

  return { context, page };
}

/** Share the open canvas with the second account, through the share dialog. */
async function shareWithSecondUser(page: Page): Promise<void> {
  await page.locator('#share-canvas-button').click();

  const dialog = page.locator('#share-canvas-dialog');
  await expect(dialog.locator('#share-canvas-dialog-form')).toBeVisible();
  await dialog.locator('#share-canvas-dialog-form input[name="email"]').fill(USER_B);
  await dialog
    .locator('#share-canvas-dialog-form')
    .getByRole('button', { name: 'Share' })
    .click();

  // The flash auto-dismisses, so the access list is the durable proof.
  await expect(dialog.locator(`li[data-email="${USER_B}"]`)).toBeVisible();
  await dismissFlash(page);
  await dialog.getByRole('button', { name: 'Done' }).click();
  await expect(dialog.locator('[data-part="content-panel"]')).toBeHidden();
}

/** The note editor starts as a preview; a click opens its textarea. */
async function openNoteEditor(page: Page): Promise<void> {
  await page.locator('#canvas-note-preview').click();
  await expect(page.locator(NOTE_INPUT)).toBeVisible();
}

// A note edit by one user has to land in the other user's editor. The
// textarea is the interesting target: it is filled by the client hook from
// the server's `note_content_updated` push, not by a re-render, so seeing the
// text there proves the whole path (context → store → broadcast → push →
// hook) and that no reload happened.
async function expectNoteText(page: Page, text: string): Promise<void> {
  await expect(page.locator(NOTE_INPUT)).toHaveValue(text, { timeout: 20_000 });
}

// Counts full page loads, so "arrives without a reload" is asserted rather
// than assumed.
function countNavigations(page: Page): () => number {
  let navigations = 0;
  page.on('framenavigated', (frame) => {
    if (frame === page.mainFrame()) navigations += 1;
  });
  return () => navigations;
}

test.describe('note collaboration', () => {
  test('a note edit reaches the other user without a reload', async ({
    page,
    browser,
    baseURL,
  }) => {
    test.setTimeout(120_000);

    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();
    await page.getByRole('button', { name: 'Start from Problem–Solution Canvas' }).click();
    await page.getByPlaceholder('Enter canvas name...').fill(uniqueName('Note Collab'));
    await page.getByRole('button', { name: 'Create Canvas' }).click();
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    await page.locator('.phx-connected').first().waitFor();
    await dismissFlash(page);

    // A note of its own: its id in the URL is how the other user opens it.
    await page.locator('#canvas-tab-notes').click();
    await page.locator('#new-note-button').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();
    await expect(page).toHaveURL(/tab=notes&note=/);
    const noteUrl = page.url();

    await shareWithSecondUser(page);

    const { context, page: pageB } = await signInAsSecondUser(browser, baseURL);
    await pageB.goto(noteUrl);
    await pageB.locator('.phx-connected').first().waitFor();
    await expect(pageB.locator('#canvas-note-title-form')).toBeVisible();

    // Both have the same note open, so each header names the other. This is
    // also the proof that both sockets are up before the typing starts: the
    // server-rendered HTML shows the note before the LiveView connects.
    await expect(page.locator('#canvas-note-presence')).toContainText(USER_B, {
      timeout: 15_000,
    });
    await expect(pageB.locator('#canvas-note-presence')).toContainText(USER_A, {
      timeout: 15_000,
    });

    const navigationsOnB = countNavigations(pageB);

    const textFromA = `A writes at ${Date.now()}`;
    await openNoteEditor(page);
    await page.locator(NOTE_INPUT).fill(textFromA);
    await expectNoteText(pageB, textFromA);

    // The other way round: B's edit lands in A's editor.
    const textFromB = `${textFromA} / B adds a line`;
    await openNoteEditor(pageB);
    await pageB.locator(NOTE_INPUT).fill(textFromB);
    await expectNoteText(page, textFromB);

    // A live update, not a reload: B never left the page.
    expect(navigationsOnB()).toBe(0);

    await context.close();
  });

  test('a scratchpad note edit reaches the other user without a reload', async ({
    page,
    browser,
    baseURL,
  }) => {
    test.setTimeout(120_000);

    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();
    await page.getByRole('button', { name: 'Start from Scratchpad' }).click();
    await page.getByPlaceholder('Enter canvas name...').fill(uniqueName('Scratchpad Collab'));
    await page.getByRole('button', { name: 'Create Canvas' }).click();
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    await page.locator('.phx-connected').first().waitFor();
    await dismissFlash(page);

    // Opening the Notes view creates the one note on the server; there is no
    // note id in the URL to share, because there is nothing to choose.
    await page.locator('#canvas-tab-notes').click();
    await expect(page.locator('#canvas-note-title-form')).toBeVisible();
    await expect(page.locator('#canvas-notes-list')).toHaveCount(0);
    const noteUrl = page.url();

    await shareWithSecondUser(page);

    const { context, page: pageB } = await signInAsSecondUser(browser, baseURL);
    await pageB.goto(noteUrl);
    await pageB.locator('.phx-connected').first().waitFor();
    await expect(pageB.locator('#canvas-note-title-form')).toBeVisible();

    // There is no note id to name, so presence is the proof that both users
    // are on the same scratchpad note before the typing starts.
    await expect(page.locator('#canvas-note-presence')).toContainText(USER_B, {
      timeout: 15_000,
    });
    await expect(pageB.locator('#canvas-note-presence')).toContainText(USER_A, {
      timeout: 15_000,
    });

    const navigationsOnB = countNavigations(pageB);

    const textFromA = `scratch from A ${Date.now()}`;
    await openNoteEditor(page);
    await page.locator(NOTE_INPUT).fill(textFromA);
    await expectNoteText(pageB, textFromA);

    const textFromB = `${textFromA} + B`;
    await openNoteEditor(pageB);
    await pageB.locator(NOTE_INPUT).fill(textFromB);
    await expectNoteText(page, textFromB);

    expect(navigationsOnB()).toBe(0);

    await context.close();
  });
});
