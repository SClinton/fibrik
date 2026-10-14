import { defineConfig, devices } from "@playwright/test";

// Runs against a deployed Fibrik (make e2e-ui port-forwards Caddy to 8080).
export default defineConfig({
  testDir: "e2e",
  timeout: 60_000,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: process.env.FIBRIK_URL ?? "http://localhost:8080",
    trace: "retain-on-failure",
    // Optional: use an already-installed Chromium instead of downloading one.
    launchOptions: { executablePath: process.env.PW_CHROMIUM_PATH || undefined },
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
