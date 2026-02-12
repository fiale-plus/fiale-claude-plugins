const INTERACTIVE_ROLES = new Set([
  'button', 'link', 'textbox', 'combobox', 'checkbox',
  'radio', 'tab', 'menuitem', 'switch', 'searchbox',
]);

export function getInteractiveElements(snapshot, elements = [], parent = null) {
  if (!snapshot) return elements;

  if (INTERACTIVE_ROLES.has(snapshot.role) && snapshot.name) {
    elements.push({
      ref: elements.length + 1,
      role: snapshot.role,
      name: snapshot.name,
      value: snapshot.value,
    });
  }

  if (snapshot.children) {
    for (const child of snapshot.children) {
      getInteractiveElements(child, elements, snapshot);
    }
  }

  return elements;
}

export function formatElements(elements) {
  if (elements.length === 0) return '';
  return elements.map(el => {
    let line = `[${el.ref}] ${el.role} "${el.name}"`;
    if (el.value) line += ` = "${el.value}"`;
    return line;
  }).join('\n');
}

function ariaSelector(el) {
  // Escape brackets, quotes, and backslashes in name to avoid breaking the selector
  const name = el.name.replace(/[\\[\]"']/g, '\\$&');
  return `::-p-aria(${name}[role="${el.role}"])`;
}

function resolveElement(target, elements) {
  const ref = parseInt(target, 10);
  if (!isNaN(ref)) {
    const el = elements.find(e => e.ref === ref);
    if (!el) throw new Error(`Element not found: ref [${ref}]`);
    return ariaSelector(el);
  }
  // Escape backslashes and parentheses to avoid breaking the selector
  const escaped = target.replace(/[\\()]/g, '\\$&');
  return `::-p-text(${escaped})`;
}

export async function resolveAndClick(page, target, elements) {
  const selector = resolveElement(target, elements);
  const handle = await page.waitForSelector(selector, { timeout: 5000 });
  if (!handle) throw new Error(`Element not found: ${target}`);
  await handle.click();
}

export async function resolveAndType(page, target, value, elements) {
  const selector = resolveElement(target, elements);
  const handle = await page.waitForSelector(selector, { timeout: 5000 });
  if (!handle) throw new Error(`Element not found: ${target}`);
  await handle.click({ clickCount: 3 }); // select existing text
  await handle.type(value);
}
