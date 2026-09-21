import { defineConfig, devices } from '@playwright/test';

const BASE_URL = 'http://localhost:4001';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  globalSetup: './global-setup.ts',
  projects: [
    {
      name: 'setup',
      testMatch: /auth\.setup\.ts/,
    },
    {
      name: 'chromium',
      testIgnore: /auth\.setup\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        storageState: '.auth/user.json',
      },
      dependencies: ['setup'],
    },
  ],
  webServer: {
    command: 'mix phx.server',
    cwd: '../..',
    url: BASE_URL,
    reuseExistingServer: true,
    timeout: 120_000,
    // Runs the dev build (already compiled) against a separate DB and port,
    // so no dependency recompilation is needed.
    env: { MIX_ENV: 'dev', PSC_DB_NAME: 'psc_e2e', PSC_PORT: '4001' },
  },
});