export async function renderPage(url, { cookies, timeout = 30000 } = {}) {
  let puppeteer;
  try {
    puppeteer = await import('puppeteer');
  } catch {
    throw new Error(
      'Headless rendering requires puppeteer.\n' +
      'Install it with: npm install puppeteer'
    );
  }

  const browser = await puppeteer.default.launch({ headless: true });
  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(timeout);

    if (cookies) {
      const { hostname } = new URL(url);
      const cookieObjects = cookies.split('; ').map(c => {
        const [name, ...rest] = c.split('=');
        return { name, value: rest.join('='), domain: `.${hostname}`, path: '/' };
      });
      await page.setCookie(...cookieObjects);
    }

    await page.goto(url, { waitUntil: 'networkidle2', timeout });
    const html = await page.content();
    return html;
  } finally {
    await browser.close().catch(() => {});
  }
}
