import { expect, test } from "@playwright/test";

// Week-1 exit check: sign in through Dex (mock connector in CI) and see the
// pipeline counts that the API reads from ClickHouse and Iceberg.
test("sign in and see pipeline stats", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Sign in" }).click();
  // Dex with a single connector skips the chooser; the mock connector
  // signs in without a form and redirects back.
  await expect(page.getByTestId("user-name")).toBeVisible({ timeout: 30_000 });
  await expect(page.getByTestId("stat-hot")).toHaveText(/^\d+$/, { timeout: 30_000 });
  await expect(page.getByTestId("stat-lake")).toHaveText(/^\d+$/);
});
