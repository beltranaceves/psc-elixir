import { test, expect, type Page } from '@playwright/test';

/**
 * Unstructured canvas editor (/canvas) E2E tests.
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

/**
 * Read a computed colour once it has stopped changing.
 *
 * The badges animate their colour (`transition-colors`), so reading the
 * value right after a state change catches an intermediate frame.
 */
async function settledColour(page: Page, selector: string): Promise<string> {
  let last: string | null = null;
  await expect
    .poll(
      async () => {
        const value = await page
          .locator(selector)
          .evaluate((el) => getComputedStyle(el).color);
        const stable = value === last;
        last = value;
        return stable;
      },
      { timeout: 5000 },
    )
    .toBe(true);
  return last as unknown as string;
}

/** Create a canvas from the index page and open its editor. */
async function createCanvasAndOpen(page: Page, name: string): Promise<string> {
  await page.goto('/canvas');
  await page.locator('.phx-connected').first().waitFor();

  // The helpers need a canvas with structure to edit: the PSC card, not the
  // default blank (which is empty until the owner builds it in place).
  await page.getByRole('button', { name: 'Start from Problem–Solution Canvas' }).click();
  await page.getByPlaceholder('Enter canvas name...').fill(name);
  await page.getByRole('button', { name: 'Create Canvas' }).click();

  // Creating lands the user in the canvas they asked for.
  await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
  await expect(page.locator('#canvas-name-form')).toBeVisible();
  // The tab strip switches client-side and patches the server; clicking a tab
  // before the socket is up gets the first render's Editor tab patched back
  // over the choice.
  await page.locator('.phx-connected').first().waitFor();

  await dismissFlash(page);
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

test.describe('canvas editor mobile fullscreen cells', () => {
  test('fullscreens a tapped cell, edits, swipes between cells and returns', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createCanvasAndOpen(page, uniqueName('Mobile Cell'));

    const expanded = page.locator('.canvas-cell.is-expanded');
    const card = page.locator('.canvas-cell').first();
    await expect(card).toBeVisible();

    // First tap: the cell animates into the whole viewport, no editor yet.
    await card.click({ position: { x: 14, y: 12 } });
    await expect(card).toHaveClass(/is-expanded/);
    await expect(card).toHaveCSS('animation-name', 'cell-fullscreen-in');
    // The entrance animation scales the card; wait for its final size.
    await expect
      .poll(async () => {
        const box = await card.boundingBox();
        return box ? [Math.round(box.width), Math.round(box.height)] : null;
      })
      .toEqual([390, 844]);
    await expect(page.locator('[data-cell-exit]').first()).toBeVisible();

    const swipe = async (fromX: number, fromY: number, toX: number, toY: number) => {
      await page.mouse.move(fromX, fromY);
      await page.mouse.down();
      await page.mouse.move(toX, toY, { steps: 8 });
      await page.mouse.up();
    };

    // Swipe left → next column, swipe right → back.
    await swipe(320, 420, 180, 420);
    await expect(page.locator('.canvas-cell.is-expanded')).toHaveCount(1);
    await expect(expanded).toHaveAttribute('data-cell-key', 'leverage');
    await swipe(120, 420, 280, 420);
    await expect(page.locator('.canvas-cell.is-expanded')).toHaveCount(1);
    await expect(expanded).toHaveAttribute('data-cell-key', 'problem');

    // Swipe up → next row, swipe down → back. A swipe never opens the editor.
    await swipe(200, 500, 200, 350);
    await expect(page.locator('.canvas-cell.is-expanded')).toHaveCount(1);
    await expect(expanded).toHaveAttribute('data-cell-key', 'outer_environment');
    await expect(expanded.locator('textarea:visible')).toHaveCount(0);
    await swipe(200, 350, 200, 520);
    await expect(page.locator('.canvas-cell.is-expanded')).toHaveCount(1);
    await expect(expanded).toHaveAttribute('data-cell-key', 'problem');

    // Second tap: the field opens for editing inside the fullscreen cell.
    await card.locator('.cell-body').click({ position: { x: 40, y: 60 } });
    await expect(card.locator('textarea:visible')).toHaveCount(1);

    // The floating button returns to the grid and ends editing. The exit
    // animation is short-lived, so assert the resulting state, not the frame.
    await page.locator('[data-cell-exit]').first().click({ force: true });
    await expect(card).not.toHaveClass(/is-expanded/, { timeout: 2000 });
    await expect(page.locator('[data-cell-exit]').first()).toBeHidden();
    await expect(card.locator('textarea:visible')).toHaveCount(0);
  });

  test('the fullscreen cell lives in the URL, so Back returns to the canvas', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    const url = await createCanvasAndOpen(page, uniqueName('Fullscreen URL'));

    const card = page.locator('.canvas-cell').first();
    await card.click({ position: { x: 14, y: 12 } });
    await expect(page.locator('.canvas-cell.is-expanded')).toHaveCount(1);

    // The fullscreen view is a URL state, so it can be linked and reloaded.
    await expect(page).toHaveURL(/#cell-/);

    // Back leaves the fullscreen view, not the canvas.
    await page.goBack();
    await expect(page).not.toHaveURL(/#cell-/);
    await expect(page.locator('.canvas-cell.is-expanded')).toHaveCount(0);
    await expect(page.locator('#canvas-grid')).toBeVisible();
    expect(page.url()).toContain(url.split('#')[0]);
  });

  test('the share modal does not scroll the canvas behind it', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createCanvasAndOpen(page, uniqueName('Share Scroll'));

    const main = page.locator('main');
    const before = await main.evaluate(el => el.scrollTop);

    await page.getByRole('button', { name: 'Share' }).click({ force: true });
    await expect(page.locator('#share-canvas-dialog [data-part="content-panel"]')).toBeVisible();

    // The dialog is moved with `top`; it never scrolls the page.
    expect(await main.evaluate(el => el.scrollTop)).toBe(before);
    expect(await page.evaluate(() => window.scrollY)).toBe(0);
  });

  test('the share modal stays on screen when the keyboard is open', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createCanvasAndOpen(page, uniqueName('Keyboard Modal'));

    // Stand in for the on-screen keyboard: the visible viewport is shorter
    // than the layout viewport, which is what the dialog has to follow.
    await page.evaluate(() => {
      const real = window.visualViewport;
      Object.defineProperty(window, 'visualViewport', {
        configurable: true,
        get: () => ({
          get height() {
            return 400;
          },
          get width() {
            return real.width;
          },
          get offsetTop() {
            return 0;
          },
          get offsetLeft() {
            return 0;
          },
          get scale() {
            return 1;
          },
          addEventListener() {},
          removeEventListener() {},
        }),
      });
    });

    await page.getByRole('button', { name: 'Share' }).click({ force: true });
    const panel = page.locator('#share-canvas-dialog [data-part="content-panel"]');
    await expect(panel).toBeVisible();

    // The open animation overrides the panel's size while it runs; wait for it
    // to settle before measuring.
    await expect
      .poll(async () => panel.evaluate(el => getComputedStyle(el).maxHeight))
      .toBe('368px');

    const box = await panel.boundingBox();
    expect(box).not.toBeNull();
    // The whole panel is on screen, and above the keyboard.
    expect(box!.x).toBeGreaterThanOrEqual(0);
    expect(box!.x + box!.width).toBeLessThanOrEqual(390);
    expect(box!.y).toBeGreaterThanOrEqual(0);
    expect(box!.y + box!.height).toBeLessThanOrEqual(400);

    // The panel is centred with the `translate` property, which a transform
    // on top of it would double up and push half the panel off the screen.
    const transform = await panel.evaluate(el => el.style.transform);
    expect(transform).toBe('');
  });

  test('a touch tap only expands the cell — no instant edit — and swipes navigate', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });    await createCanvasAndOpen(page, uniqueName('Touch Cell'));

    // Real touch events (the phone path): the markdown display has its own
    // click listener, so a tap must not slip through into edit mode.
    const client = await page.context().newCDPSession(page);
    await client.send('Emulation.setTouchEmulationEnabled', {
      enabled: true,
      maxTouchPoints: 1,
    });

    const touch = async (type: string, points: { x: number; y: number }[]) => {
      await client.send('Input.dispatchTouchEvent', { type, touchPoints: points });
    };

    const tap = async (x: number, y: number) => {
      await touch('touchStart', [{ x, y }]);
      await touch('touchEnd', []);
    };

    const swipe = async (x1: number, y1: number, x2: number, y2: number) => {
      await touch('touchStart', [{ x: x1, y: y1 }]);
      for (let i = 1; i <= 6; i++) {
        await touch('touchMove', [
          { x: x1 + ((x2 - x1) * i) / 6, y: y1 + ((y2 - y1) * i) / 6 },
        ]);
      }
      await touch('touchEnd', []);
    };

    const expanded = page.locator('.canvas-cell.is-expanded');
    const card = page.locator('.canvas-cell').first();
    await expect(card).toBeVisible();

    // Record the directional swipe classes as they are applied.
    await page.evaluate(() => {
      (window as any).__swipeClasses = [];
      const observer = new MutationObserver(() => {
        document.querySelectorAll('.canvas-cell').forEach(cell => {
          Array.from(cell.classList).forEach(name => {
            if (name.startsWith('is-swipe-') && !(window as any).__swipeClasses.includes(name)) {
              (window as any).__swipeClasses.push(name);
            }
          });
        });
      });
      observer.observe(document.body, {
        attributes: true,
        subtree: true,
        attributeFilter: ['class'],
      });
    });

    const spot = await card.evaluate(el => {
      const r = el.getBoundingClientRect();
      return { x: Math.round(r.left + 20), y: Math.round(r.top + 14) };
    });

    // Tap: full screen, still read-only.
    await tap(spot.x, spot.y);
    await expect(expanded).toHaveAttribute('data-cell-key', 'problem');
    await expect(page.locator('.canvas-cell textarea:visible')).toHaveCount(0);

    // Swipe left → next column, swipe up → next row; still read-only.
    await swipe(320, 420, 170, 420);
    await expect(page.locator('.canvas-cell.is-expanded')).toHaveCount(1);
    await expect(expanded).toHaveAttribute('data-cell-key', 'leverage');
    await swipe(200, 500, 200, 340);
    await expect(page.locator('.canvas-cell.is-expanded')).toHaveCount(1);
    await expect(expanded).toHaveAttribute('data-cell-key', 'inner_environment');
    await expect(page.locator('.canvas-cell textarea:visible')).toHaveCount(0);

    // The cells slide in the direction of the finger.
    const swipeClasses = await page.evaluate(() => (window as any).__swipeClasses);
    expect(swipeClasses).toContain('is-swipe-out-left');
    expect(swipeClasses).toContain('is-swipe-in-right');
    expect(swipeClasses).toContain('is-swipe-out-top');
    expect(swipeClasses).toContain('is-swipe-in-bottom');

    // The transition leaves no leftovers behind.
    await expect(page.locator('.canvas-cell.is-swipe-out-left')).toHaveCount(0);
    await expect(page.locator('.canvas-cell.is-swipe-in-right')).toHaveCount(0);

    // The slide-in must not fall back to the fullscreen animation once it
    // finishes — that replay looked like the cell reloaded itself.
    await expect
      .poll(async () =>
        page.evaluate(() =>
          document.querySelector('.canvas-cell.is-expanded')?.classList.contains('is-settled'),
        ),
      )
      .toBe(true);
    const animation = await page.evaluate(() => {
      const cell = document.querySelector('.canvas-cell.is-expanded');
      return cell ? getComputedStyle(cell).animationName : null;
    });
    expect(animation).toBe('none');
  });
});

test.describe('canvas editor tabs', () => {
  test('switches between the editor grid and the placeholder views', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Tabbed Canvas'));

    const tabs = page.locator('#canvas-tabs [role="tab"]');
    await expect(tabs).toHaveCount(5);
    await expect(page.locator('#canvas-tab-editor')).toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('#canvas-grid')).toBeVisible();

    await page.locator('#canvas-tab-notes').click();
    await expect(page.locator('#canvas-tab-notes')).toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('#canvas-notes')).toBeVisible();
    // The grid stays in the DOM but is hidden, so the switch is instant.
    await expect(page.locator('#canvas-grid')).toBeHidden();
    await expect(page).toHaveURL(/tab=notes/);

    await page.locator('#canvas-tab-info').click();
    await expect(page.locator('#canvas-tab-info')).toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('#canvas-panel-info')).toBeVisible();
    await expect(page.locator('#canvas-info-details')).toBeVisible();
    await expect(page).toHaveURL(/tab=info/);

    await page.locator('#canvas-tab-editor').click();
    await expect(page.locator('#canvas-grid')).toBeVisible();

    // Tab changes replace the current canvas URL instead of adding entries.
    // Back therefore leaves the editor rather than walking through each tab.
    await page.goBack();
    await page.waitForURL(/\/canvas$/);
    await expect(page.locator('#canvas-name-form')).toHaveCount(0);
  });

  test('switches tabs without waiting for the server', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Instant Tab'));

    // Simulate a slow connection: the tab has to switch anyway, because the
    // panel is swapped on the client and the server only confirms it.
    await page.evaluate(() => window.liveSocket.enableLatencySim(1500));

    const started = Date.now();
    await page.locator('#canvas-tab-notes').click();
    await expect(page.locator('#canvas-notes')).toBeVisible();
    const elapsed = Date.now() - started;

    await page.evaluate(() => window.liveSocket.disableLatencySim());

    expect(elapsed).toBeLessThan(1000);
  });
});

test.describe('canvas editor (single player)', () => {
  test('opens the field editor when clicking anywhere in a cell', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Click Anywhere'));

    const card = page.locator('.canvas-cell').first();
    await expect(card).toBeVisible();

    // Click the cell header/padding, not the text field itself.
    await card.click({ position: { x: 12, y: 12 } });

    await expect(card.locator('textarea')).toBeVisible();
    await expect(card.locator('textarea')).toBeFocused();
  });

  test('clicking a cell without typing leaves the canvas saved', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('No-op Cell'));

    const card = page.locator('.canvas-cell').first();
    await expect(card).toBeVisible();

    // Open the field, then blur without typing. The cell hook used to send
    // `update_cell` on every blur, even when the value was unchanged.
    await card.click({ position: { x: 12, y: 12 } });
    await expect(card.locator('textarea')).toBeVisible();
    await page.getByRole('heading', { name: 'Canvas Editor' }).click();

    // Check without retrying: the 1.5s idle save would turn Unsaved back into
    // Saved and hide the regression.
    await page.waitForTimeout(400);
    expect(await page.locator('#canvas-save-state-pill').innerText()).toContain('Saved');

    await page.waitForTimeout(1_600);
    await expect(page.locator('#canvas-save-state-pill')).toContainText('Saved');
  });

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

    await page.locator('#share-canvas-button').click();
    const shareDialog = page.locator('#share-canvas-dialog');
    await expect(shareDialog.locator('#share-canvas-dialog-form')).toBeVisible();
    await shareDialog.locator('#share-canvas-dialog-form input[name="email"]').fill(USER_B);
    await shareDialog
      .locator('#share-canvas-dialog-form')
      .getByRole('button', { name: 'Share' })
      .click();
    // The flash auto-dismisses, so the access list is the durable proof that
    // the canvas was shared.
    await expect(shareDialog.locator(`li[data-email="${USER_B}"]`)).toBeVisible();
    await dismissFlash(page);
    await shareDialog.getByRole('button', { name: 'Done' }).click();
    await expect(shareDialog.locator('[data-part="content-panel"]')).toBeHidden();

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

    // --- Presence: both users see each other in the active-users tooltip ---
    const activeUsers = (p: Page) => p.locator('#active-users-tooltip');
    const expectSeesUser = async (p: Page, username: string) => {
      await expect(async () => {
        const text = await activeUsers(p).locator('[data-part="content"]').innerText();
        expect(text).toContain(username);
      }).toPass({ timeout: 15_000 });
    };
    await expectSeesUser(page, USER_B);
    await expectSeesUser(pageB, USER_A);

    // The trigger is truncated; the full list appears on hover.
    await activeUsers(page).getByRole('button').hover();
    await expect(activeUsers(page).locator('[data-part="content"]')).toBeVisible();

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

test.describe('canvas editor layout', () => {
  test('puts the canvas title in the editor toolbar and the grid full-width', async ({
    page,
  }) => {
    await createCanvasAndOpen(page, uniqueName('Layout Canvas'));

    // The title is renamed where it is read: in the layout toolbar, above the
    // table. The description is not part of the editing surface.
    const name = page.locator('#canvas-grid #canvas-name-form input');
    await expect(name).toBeVisible();
    await expect(page.locator('#canvas-panel-editor #canvas-description-form')).toHaveCount(0);

    const nameBox = await name.boundingBox();
    expect(nameBox).not.toBeNull();

    // The title leads the row; the structure toggle sits on the right.
    const toggleBox = await page.locator('#edit-structure-toggle').boundingBox();
    expect(toggleBox).not.toBeNull();
    expect(toggleBox!.x).toBeGreaterThan(nameBox!.x);

    // The toolbar sits above the header row of the table, inside the grid card.
    const grid = page.locator('#canvas-grid');
    const gridBox = await grid.boundingBox();
    expect(gridBox).not.toBeNull();
    expect(nameBox!.y).toBeGreaterThanOrEqual(gridBox!.y);
    expect(nameBox!.y).toBeLessThan(gridBox!.y + 48);

    // The editable grid itself stays visible.
    await expect(page.locator('#md-problem-content')).toBeVisible();

    // The workspace hugs the viewport (~95%) instead of a fixed 1280px cap.
    const box = await page.locator('#canvas-workspace').boundingBox();
    const viewport = page.viewportSize();
    expect(viewport).not.toBeNull();
    const ratio = box!.width / viewport!.width;
    expect(ratio).toBeGreaterThan(0.9);
    expect(ratio).toBeLessThan(0.97);
  });

  test('moves the description to the Info tab', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Info Canvas'));

    // Hidden on the editor, where the grid is the point of the screen.
    await expect(page.locator('#canvas-description-form')).toBeHidden();

    await page.locator('#canvas-tab-info').click();
    await expect(page.locator('#canvas-panel-info')).toBeVisible();
    await expect(page.locator('#canvas-info-name-form')).toBeVisible();
    await expect(page.locator('#canvas-description-form textarea')).toBeVisible();
  });

  test('ends the grid just above the app bar, without a dead band or a page scroll', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await createCanvasAndOpen(page, uniqueName('No Dead Band'));

    const grid = await page.locator('#canvas-grid').boundingBox();
    const bar = await page.locator('#canvas-tabs-bar').boundingBox();
    expect(grid).not.toBeNull();
    expect(bar).not.toBeNull();

    // The table ends a sliver above the app bar: enough to breathe, not
    // enough to become a dead band.
    const gap = bar!.y - (grid!.y + grid!.height);
    expect(gap).toBeGreaterThanOrEqual(2);
    expect(gap).toBeLessThanOrEqual(12);

    // The page itself does not scroll: the editor fills the viewport.
    const overflow = await page.evaluate(
      () => document.documentElement.scrollHeight - document.documentElement.clientHeight,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test('moves presence, save state and Share into the app header on phones', async ({
    page,
  }) => {
    await createCanvasAndOpen(page, uniqueName('Compact Header'));

    await page.setViewportSize({ width: 390, height: 844 });

    // The app header carries the minimal cluster ...
    await expect(page.locator('#canvas-presence-compact')).toBeVisible();
    await expect(page.locator('#canvas-save-state-compact')).toBeVisible();
    await expect(page.locator('#share-canvas-button-compact')).toBeVisible();

    // ... and the three read as one cluster: the same height.
    const box = async (selector: string) => {
      const b = await page.locator(selector).boundingBox();
      expect(b).not.toBeNull();
      return b!;
    };
    const presence = await box('#canvas-presence-compact');
    const status = await box('#canvas-save-state-compact');
    const share = await box('#share-canvas-button-compact');

    expect(Math.abs(presence.height - status.height)).toBeLessThanOrEqual(1);
    expect(Math.abs(status.height - share.height)).toBeLessThanOrEqual(1);

    const colours = async (selector: string) =>
      page.locator(selector).evaluate((el) => {
        const cs = getComputedStyle(el);
        return { bg: cs.backgroundColor, color: cs.color };
      });

    // The phone pill carries the same state colours as the desktop badge.
    const phoneColours = await colours('#canvas-save-state-compact');
    const desktopColours = await colours('#canvas-save-state-pill');
    expect(phoneColours.bg).toBe(desktopColours.bg);
    expect(phoneColours.color).toBe(desktopColours.color);
    // "Saved" is the primary colour, not the neutral one.
    expect(phoneColours.bg).not.toBe('rgba(0, 0, 0, 0)');

    // ... and the editor header keeps only the title and the description.
    await expect(page.locator('#canvas-presence')).toBeHidden();
    await expect(page.locator('#canvas-save-state')).toBeHidden();
    await expect(page.locator('#share-canvas-button')).toBeHidden();

    // The grid gets the vertical space back.
    const grid = await page.locator('#canvas-grid').boundingBox();
    expect(grid).not.toBeNull();
    expect(grid!.y).toBeLessThan(200);

    // The presence pill still opens the list of people on the canvas.
    await page.locator('#canvas-presence-compact').click();
    await expect(page.locator('#active-users-tooltip-compact [data-part="content"]')).toBeVisible();

    // And the compact Share button opens the dialog (it used to push an
    // unhandled event and take the LiveView down).
    await page.locator('#canvas-presence-compact').click();
    await page.locator('#share-canvas-button-compact').click();
    await expect(page.locator('#share-canvas-dialog [data-part="content-panel"]')).toBeVisible();
    await expect(page.locator('#canvas-grid')).toBeVisible();

    await page.setViewportSize({ width: 390, height: 480 });
    const panel = page.locator('#share-canvas-dialog [data-part="content-panel"]');
    const panelBox = await panel.boundingBox();
    expect(panelBox).not.toBeNull();
    expect(panelBox!.y).toBeGreaterThanOrEqual(8);
    expect(panelBox!.y + panelBox!.height).toBeLessThanOrEqual(472);
  });
});

test.describe('canvas editor status pill', () => {
  test('reports the save status on hover', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Status Pill'));

    const pill = page.locator('#canvas-save-state-pill');
    const tip = page.locator('#canvas-save-state-pill-tooltip [data-part="content"]');

    await expect(pill).toContainText('Saved');
    await expect(tip).toBeHidden();

    await pill.hover();
    await expect(tip).toBeVisible();
    await expect(tip).toContainText('Last saved');
    await expect(tip).toContainText('Writes this session');
  });

  test('counts the writes it made', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Status Writes'));

    const display = page.locator('#md-render-problem-content');
    await expect(display).toContainText('Click to edit');
    await display.click();
    const textarea = page.locator('#md-problem-content textarea');
    await textarea.fill('A write that counts');
    await textarea.blur();

    // The idle save lands 1.5 s after the last edit.
    const pill = page.locator('#canvas-save-state-pill');
    await expect(pill).toContainText('Saved', { timeout: 15_000 });

    await pill.hover();
    const tip = page.locator('#canvas-save-state-pill-tooltip [data-part="content"]');
    await expect(tip).toBeVisible();
    await expect(tip).toContainText('just now');
    await expect(tip).toContainText('Last write took');
  });

  test('marks the unsaved state with the warning colour', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Status Unsaved'));

    const pill = page.locator('#canvas-save-state-pill');
    const display = page.locator('#md-render-problem-content');
    await display.click();
    const textarea = page.locator('#md-problem-content textarea');
    await textarea.fill('Not saved yet');
    await textarea.blur();

    // The pill turns amber while the change waits for the idle save.
    await expect(pill).toContainText('Unsaved');

    const desktop = await settledColour(page, '#canvas-save-state-pill');
    // Amber, not the neutral foreground the outline variant carries.
    expect(desktop).not.toBe('rgba(0, 0, 0, 0)');
    expect(desktop).toContain('oklch');

    // The phone pill uses the same colour.
    await page.setViewportSize({ width: 390, height: 844 });
    const phone = await settledColour(page, '#canvas-save-state-compact');
    expect(phone).toBe(desktop);
  });
});

test.describe('template designer cell editing', () => {
  test('edits a cell label and fields directly in the grid and persists them', async ({
    page,
  }) => {
    const templateName = uniqueName('Inline Cells');

    await page.goto('/templates/new');
    await page.locator('.phx-connected').first().waitFor();
    await page.getByRole('button', { name: 'Add Column' }).click();
    await page.getByRole('button', { name: 'Add Row' }).click();

    // The cell itself carries the controls — no selection step, no side panel.
    const cell = page.locator('#cell-r1_c1');
    await expect(cell).toBeVisible();
    await expect(page.getByText('Select a cell in the grid')).toHaveCount(0);

    await cell.locator('#cell-r1_c1-label').fill('Problem');
    await cell.locator('#cell-r1_c1-field-content').fill('Write the problem');
    await cell.locator('#cell-r1_c1-new-field').fill('evidence');
    await cell.getByRole('button', { name: 'Add' }).click();
    await expect(cell.locator('#cell-r1_c1-field-evidence')).toBeVisible();

    // Header labels are inline forms too.
    await page.locator('#column-c1-label').fill('Perceive');
    await page.locator('#row-r1-label').fill('Rationale');

    await page.locator('#template-form input[name="name"]').fill(templateName);
    await page.getByRole('button', { name: 'Save Template' }).click();
    await page.waitForURL(/\/templates$/);

    // Reopen from the library and confirm the inline edits were persisted.
    const card = page
      .getByRole('heading', { name: templateName })
      .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
    await card.getByRole('link', { name: 'Edit' }).click();
    await page.waitForURL(/\/templates\/[0-9a-f-]{36}/);

    await expect(page.locator('#cell-r1_c1-label')).toHaveValue('Problem');
    await expect(page.locator('#cell-r1_c1-field-content')).toHaveValue('Write the problem');
    await expect(page.locator('#cell-r1_c1-field-evidence')).toBeVisible();
    await expect(page.locator('#column-c1-label')).toHaveValue('Perceive');
    await expect(page.locator('#row-r1-label')).toHaveValue('Rationale');
  });
});

test.describe('template designer saving', () => {
  test('warns about unsaved changes and cancels back to the library', async ({ page }) => {
    const discarded = uniqueName('Discarded template');

    await page.goto('/templates/new');
    await page.locator('.phx-connected').first().waitFor();

    // Templates are saved explicitly — nothing is dirty on a fresh page.
    await expect(page.locator('#unsaved-changes-hint')).toHaveCount(0);

    await page.locator('#template-form input[name="name"]').fill(discarded);
    await page.getByRole('button', { name: 'Add Column' }).click();
    await expect(page.locator('#unsaved-changes-hint')).toBeVisible();

    // Cancelling opens a confirmation modal — not a native dialog.
    await page.locator('#cancel-template-editing').click();
    const modal = page.locator('#discard-template-dialog [data-part="content-panel"]');
    await expect(modal).toBeVisible();
    await expect(modal).toContainText('Discard unsaved changes?');

    // Escape closes the modal and keeps the draft on screen.
    await page.keyboard.press('Escape');
    await expect(modal).toBeHidden();
    await expect(page.getByRole('heading', { name: 'Grid' })).toBeVisible();
    await expect(page.locator('#unsaved-changes-hint')).toBeVisible();

    // Discarding leaves the designer without persisting anything.
    await page.locator('#cancel-template-editing').click();
    await expect(modal).toBeVisible();
    await page.locator('#discard-template-changes').click();
    await page.waitForURL(/\/templates$/);

    await expect(page.getByRole('heading', { name: discarded })).toHaveCount(0);
  });
});

test.describe('canvas accents', () => {
  test('renders template accents read-only in the canvas editor', async ({ page }) => {
    const templateName = uniqueName('Read-only Accents');

    // Author accents once, in the template designer.
    await page.goto('/templates/new');
    await page.locator('.phx-connected').first().waitFor();
    await page.getByRole('button', { name: 'Add Column' }).click();
    await page.getByRole('button', { name: 'Add Row' }).click();

    await page.locator('#accent-swatch-column-c1').click();
    await page.locator('#accent-option-column-c1-sky').click();
    await page.locator('#accent-swatch-row-r1').click();
    await page.locator('#accent-option-row-r1-amber').click();

    await page.locator('#template-form input[name="name"]').fill(templateName);
    await page.getByRole('button', { name: 'Save Template' }).click();
    await page.waitForURL(/\/templates$/);

    // A canvas built from it shows the bars and offers no color controls.
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();
    const canvasName = uniqueName('Read-only canvas');
    await page.getByPlaceholder('Enter canvas name...').fill(canvasName);
    await page.getByRole('button', { name: `Start from ${templateName}` }).click();
    await page.getByRole('button', { name: 'Create Canvas' }).click();

    // Creating lands the user in the new canvas.
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    await dismissFlash(page);

    await expect(page.locator('#accent-bar-column-c1')).toHaveClass(/bg-sky-400/);
    await expect(page.locator('#accent-bar-row-r1')).toHaveClass(/bg-amber-400/);
    await expect(page.locator('[id^="accent-swatch-"]')).toHaveCount(0);
    await expect(page.locator('[id^="accent-picker-"]')).toHaveCount(0);
  });
});

test.describe('canvas color pickers', () => {
  test('a click outside the colors panel closes it', async ({ page }) => {
    await createCanvasAndOpen(page, uniqueName('Dismiss Colors'));

    await page.locator('#edit-structure-toggle').click();
    await page.locator('#cell-colors-problem').click();
    await expect(page.locator('#cell-colors-panel-problem')).toBeVisible();

    // A click inside the panel (not on a swatch) leaves it open.
    await page.locator('#cell-colors-panel-problem').click();
    await expect(page.locator('#cell-colors-panel-problem')).toBeVisible();

    // A click anywhere else dismisses it.
    await page.locator('#canvas-name-form input').click();
    await expect(page.locator('#cell-colors-panel-problem')).toBeHidden();
  });
});

test.describe('template designer accents', () => {
  test('styles headers in the designer and carries the accents into a new canvas', async ({
    page,
  }) => {
    const templateName = uniqueName('Accented Template');

    await page.goto('/templates/new');
    await page.locator('.phx-connected').first().waitFor();

    await page.getByRole('button', { name: 'Add Column' }).click();
    await page.getByRole('button', { name: 'Add Row' }).click();

    // Live preview: choosing a color paints the header bar before saving.
    await page.locator('#accent-swatch-column-c1').click();
    await expect(page.locator('#accent-picker-column-c1')).toBeVisible();
    await page.locator('#accent-option-column-c1-violet').click();
    await expect(page.locator('#accent-bar-column-c1')).toHaveClass(/bg-violet-400/);

    await page.locator('#accent-swatch-row-r1').click();
    await page.locator('#accent-option-row-r1-teal').click();
    await expect(page.locator('#accent-bar-row-r1')).toHaveClass(/bg-teal-400/);

    // The row bar spans the whole row height, not just the label line.
    const designerBar = await page.locator('#accent-bar-row-r1').boundingBox();
    const designerRow = await page.locator('tbody tr').first().boundingBox();
    expect(designerBar!.height).toBeGreaterThan(designerRow!.height - 6);

    await page.locator('#template-form input[name="name"]').fill(templateName);
    await page.getByRole('button', { name: 'Save Template' }).click();
    await page.waitForURL(/\/templates$/);

    // The designer persists accents with the layout.
    const card = page
      .getByRole('heading', { name: templateName })
      .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
    await card.getByRole('link', { name: 'Edit' }).click();
    await page.waitForURL(/\/templates\/[0-9a-f-]{36}/);
    await expect(page.locator('#accent-bar-column-c1')).toHaveClass(/bg-violet-400/);
    await expect(page.locator('#accent-bar-row-r1')).toHaveClass(/bg-teal-400/);

    // A canvas instantiated from that template inherits the accents.
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();
    const canvasName = uniqueName('Inherited Accents');
    await page.getByPlaceholder('Enter canvas name...').fill(canvasName);
    await page.getByRole('button', { name: `Start from ${templateName}` }).click();
    await page.getByRole('button', { name: 'Create Canvas' }).click();

    // Creating lands the user in the new canvas.
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    await dismissFlash(page);

    await expect(page.locator('#accent-bar-column-c1')).toHaveClass(/bg-violet-400/);
    await expect(page.locator('#accent-bar-row-r1')).toHaveClass(/bg-teal-400/);

    // The row/column colour combination belongs to the fullscreen cell view, so
    // it stays hidden in the grid.
    await expect(page.locator('#accent-bar-cell-r1_c1-column')).toBeHidden();
    await expect(page.locator('#accent-bar-cell-r1_c1-row')).toBeHidden();

    // On a phone the fullscreen cell shows the combination of both colours.
    await page.setViewportSize({ width: 390, height: 844 });

    // The first tap only expands a cell while the mobile query matches, and the
    // hook must be mounted to receive it. Poll both instead of sleeping for a
    // fixed 400 ms: under load the layout can settle later, and the click was
    // then a no-op, which made this test intermittently fail.
    await expect
      .poll(() => page.evaluate(() => window.matchMedia('(max-width: 639px)').matches))
      .toBe(true);

    await page.waitForFunction(() => {
      const cell = document.querySelector('#cell-card-r1_c1') as
        | (Element & { _cellFocus?: unknown })
        | null;
      return Boolean(cell && cell._cellFocus);
    });

    // Resolve the cell inside the page: a handle captured before a LiveView
    // patch can point at a detached node, and a click on it expands nothing.
    await page.evaluate(() => {
      const el = document.querySelector('#cell-card-r1_c1')!;
      const r = el.getBoundingClientRect();
      el.dispatchEvent(
        new MouseEvent('click', {
          bubbles: true,
          cancelable: true,
          clientX: r.left + 14,
          clientY: r.top + 12,
        }),
      );
    });
    await expect(page.locator('#accent-bar-cell-r1_c1-column')).toBeVisible();
    await expect(page.locator('#accent-bar-cell-r1_c1-row')).toBeVisible();
    await expect(page.locator('#accent-bar-cell-r1_c1-column')).toHaveClass(/bg-violet-400/);
    await expect(page.locator('#accent-bar-cell-r1_c1-row')).toHaveClass(/bg-teal-400/);

    // The read-only bar also spans the whole row height.
    const canvasBar = await page.locator('#accent-bar-row-r1').boundingBox();
    const canvasRow = await page.locator('tbody tr').first().boundingBox();
    expect(canvasBar!.height).toBeGreaterThan(canvasRow!.height - 6);
  });
});

test.describe('canvas list layout', () => {
  test('aligns card actions when one canvas has no description', async ({ page }) => {
    const emptyDescriptionName = uniqueName('No description');
    const describedName = uniqueName('With description');

    const createCanvas = async (name: string, description?: string) => {
      await page.goto('/canvas');
      await page.locator('.phx-connected').first().waitFor();
      await page.getByPlaceholder('Enter canvas name...').fill(name);

      if (description) {
        await page.getByPlaceholder('Enter canvas description...').fill(description);
      }

      await page.getByRole('button', { name: 'Create Canvas' }).click();
      await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    };

    await createCanvas(emptyDescriptionName);
    await createCanvas(
      describedName,
      'A description makes this card taller than the card above it.',
    );

    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();

    const emptyCard = page
      .getByRole('heading', { name: emptyDescriptionName, exact: true })
      .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
    const describedCard = page
      .getByRole('heading', { name: describedName, exact: true })
      .locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');

    const emptyCardBox = await emptyCard.boundingBox();
    const describedCardBox = await describedCard.boundingBox();
    const emptyEdit = await emptyCard.getByRole('link', { name: 'Edit' }).boundingBox();
    const describedEdit = await describedCard.getByRole('link', { name: 'Edit' }).boundingBox();
    expect(emptyEdit).not.toBeNull();
    expect(describedEdit).not.toBeNull();
    expect(emptyCardBox).not.toBeNull();
    expect(describedCardBox).not.toBeNull();

    // The actions sit the same distance from the bottom of their card whether
    // or not the card has a description. Comparing the offsets rather than
    // absolute positions keeps the assertion true when the two cards land in
    // different rows: other tests create canvases on this account at the same
    // time, and any of them can come between these two in the list.
    const emptyOffset = emptyEdit!.y + emptyEdit!.height - (emptyCardBox!.y + emptyCardBox!.height);
    const describedOffset =
      describedEdit!.y + describedEdit!.height - (describedCardBox!.y + describedCardBox!.height);

    expect(Math.abs(emptyOffset - describedOffset)).toBeLessThan(2);
  });
});

test.describe('mobile flash placement', () => {
  test('places feedback cards above the mobile tab bar', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();

    await page.getByPlaceholder('Enter canvas name...').fill(uniqueName('Mobile Toast'));
    await page.getByRole('button', { name: 'Create Canvas' }).click();

    const flash = page.locator('#flash-group');
    // Creating lands the user in the new canvas, whose editor also carries a
    // bottom tab bar on phones — the flash has to clear it there too.
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    await expect(flash).toContainText('Canvas created successfully', { timeout: 30_000 });
    const box = await flash.boundingBox();
    expect(box).not.toBeNull();
    expect(box!.y).toBeGreaterThan(844 / 2);
    expect(box!.y + box!.height).toBeLessThan(844 - 56);
  });
});

test.describe('canvas library', () => {
  test('keeps a long description inside its card', async ({ page }) => {
    const name = uniqueName('Long Description');
    const longWord = 'SupercalifragilisticexpialidociousWithoutAnySpacesAtAll';

    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();

    await page.getByPlaceholder('Enter canvas name...').fill(name);
    await page.getByPlaceholder('Enter canvas description...').fill(longWord);
    await page.getByRole('button', { name: 'Create Canvas' }).click();

    // Creating lands the user in the editor; the card is measured back on the
    // library, where it is listed.
    await page.waitForURL(/\/canvas\/[0-9a-f-]{36}/);
    await page.goto('/canvas');
    await page.locator('.phx-connected').first().waitFor();

    const card = page.getByRole('heading', { name }).locator('xpath=ancestor::div[contains(@class,"rounded-xl")][1]');
    const description = card.locator('p').first();

    await expect(card).toBeVisible({ timeout: 15_000 });
    await expect(description).toBeVisible();
    await dismissFlash(page);

    // The text must not paint outside the card it belongs to.
    const cardBox = await card.boundingBox();
    const descriptionBox = await description.boundingBox();
    expect(cardBox).not.toBeNull();
    expect(descriptionBox).not.toBeNull();
    expect(descriptionBox!.x).toBeGreaterThanOrEqual(cardBox!.x - 1);
    expect(descriptionBox!.x + descriptionBox!.width).toBeLessThanOrEqual(
      cardBox!.x + cardBox!.width + 1,
    );

    // The card itself must not grow past its column.
    const overflow = await card.evaluate((el) => el.scrollWidth - el.clientWidth);
    expect(overflow).toBeLessThanOrEqual(1);
  });
});
