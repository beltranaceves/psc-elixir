import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Ensures the e2e database exists, is migrated, and has the seed user,
 * and that frontend assets are built.
 *
 * Runs the dev build (already compiled) against the psc_e2e database via
 * env-var overrides, so no dependency recompilation is needed.
 *
 * Runs from the project root (two levels up from test/e2e).
 */
export default function globalSetup(): void {
  const root = join(__dirname, '..', '..');
  const env = { ...process.env, MIX_ENV: 'dev', PSC_DB_NAME: 'psc_e2e', PSC_PORT: '4001' };

  execSync('mix ecto.create --quiet', { cwd: root, env, stdio: 'inherit' });
  execSync('mix ecto.migrate --quiet', { cwd: root, env, stdio: 'inherit' });
  execSync('mix run priv/repo/e2e_seeds.exs', { cwd: root, env, stdio: 'inherit' });

  const appJs = join(root, 'priv', 'static', 'assets', 'js', 'app.js');
  if (!existsSync(appJs)) {
    execSync('mix assets.build', { cwd: root, env, stdio: 'inherit' });
  }
}