const { test, expect } = require('playwright/test');

test('diagnose production SOA', async ({ page }) => {
  const errors = [];
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(`console: ${message.text()}`);
  });
  page.on('pageerror', (error) => errors.push(`page: ${error.message}`));
  await page.goto(process.env.SOA_TEST_URL, { waitUntil: 'networkidle' });
  const heading = await page.locator('main h1').first().textContent();
  console.log(JSON.stringify({ heading, errors }));
  expect(errors).toEqual([]);
});
