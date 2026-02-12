import { openSession, getSession, closeSession } from './session.js';
import { getInteractiveElements, formatElements, resolveAndClick, resolveAndType } from './interact.js';
import { htmlToMarkdown } from './convert.js';

async function readPageState(page) {
  const html = await page.content();
  const url = page.url();
  const md = htmlToMarkdown(html, url, { useReadability: false });
  const snapshot = await page.accessibility.snapshot();
  const elements = getInteractiveElements(snapshot);
  const elementsList = formatElements(elements);

  let output = md;
  if (elementsList) {
    output += '\n\n---\n' + elementsList;
  }
  return { output, elements };
}

async function waitForSettle(page) {
  // Wait for navigation (if click triggered one) or network idle
  await Promise.race([
    page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 5000 }),
    page.waitForNetworkIdle({ timeout: 3000 }),
  ]).catch(() => {});
}

export async function actOpen(url, { cookies, timeout } = {}) {
  const { browser, page } = await openSession(url, { cookies, timeout });
  const { output } = await readPageState(page);
  browser.disconnect();
  return output;
}

export async function actClick(target) {
  const { browser, page } = await getSession();
  try {
    const snapshot = await page.accessibility.snapshot();
    const elements = getInteractiveElements(snapshot);
    await resolveAndClick(page, target, elements);
    await waitForSettle(page);
    const { output } = await readPageState(page);
    return output;
  } finally {
    browser.disconnect();
  }
}

export async function actType(target, value) {
  const { browser, page } = await getSession();
  try {
    const snapshot = await page.accessibility.snapshot();
    const elements = getInteractiveElements(snapshot);
    await resolveAndType(page, target, value, elements);
    await waitForSettle(page);
    const { output } = await readPageState(page);
    return output;
  } finally {
    browser.disconnect();
  }
}

export async function actRead() {
  const { browser, page } = await getSession();
  try {
    const { output } = await readPageState(page);
    return output;
  } finally {
    browser.disconnect();
  }
}

export async function actClose() {
  await closeSession();
  return 'Session closed.';
}
