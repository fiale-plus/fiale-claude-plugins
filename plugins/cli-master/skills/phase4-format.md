---
name: phase4-format
description: Build output formatters — markdown tables for lists, structured text for details, JSON mode
---

# Phase 4: Output Formatters

Build clean, consistent output formatters for each command. Support both human-readable markdown and machine-readable JSON.

## Architecture Pattern

One formatter function per command that takes `(data, { json = false })`:

```js
export function formatOrders(orders, { json = false } = {}) {
  if (json) return JSON.stringify(orders, null, 2);
  // markdown formatting below
}
```

## List View: Markdown Tables

Use markdown tables for list commands (orders, favorites, search results):

```js
const rows = [
  '| ID | Date | Restaurant | Total |',
  '|----|------|------------|-------|',
  ...orders.map(o =>
    `| ${o.id} | ${formatDate(o.created)} | ${o.venue?.name ?? '—'} | ${formatPrice(o.total)} |`
  )
];
return rows.join('\n');
```

## Detail View: Structured Text

Use structured text with bold labels for detail commands (single order, restaurant details):

```js
const lines = [
  `**Order:** ${order.id}`,
  `**Date:** ${formatDate(order.created)}`,
  `**Restaurant:** ${order.venue?.name ?? '—'}`,
  `**Status:** ${order.status}`,
  '',
  '**Items:**',
  ...order.items.map(item =>
    `  - ${item.name} × ${item.count} — ${formatPrice(item.price)}`
  ),
  '',
  `**Total:** ${formatPrice(order.total)}`
];
return lines.join('\n');
```

## Helper Functions

### Extract Arrays from API Responses

Handle various API shapes (data.results, data.items, data[], etc.):

```js
function extractArray(response) {
  if (Array.isArray(response)) return response;
  if (response.results) return response.results;
  if (response.items) return response.items;
  if (response.data && Array.isArray(response.data)) return response.data;
  return [];
}
```

### Date Formatting

```js
function formatDate(dateString) {
  if (!dateString) return '—';
  try {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  } catch {
    return dateString;
  }
}
```

### Price Formatting

Handle cents-to-currency conversion and price objects:

```js
function formatPrice(price) {
  if (price == null) return '—';

  // Handle price objects: { amount: 1250, currency: "EUR" }
  if (typeof price === 'object') {
    const amount = price.amount ?? price.value ?? 0;
    const currency = price.currency ?? 'EUR';
    return `${(amount / 100).toFixed(2)} ${currency}`;
  }

  // Handle raw cents
  if (typeof price === 'number') {
    return `${(price / 100).toFixed(2)} EUR`;
  }

  return String(price);
}
```

## Resilience Best Practices

- Use optional chaining: `order.venue?.name` instead of `order.venue.name`
- Provide fallback values: `order.total ?? 0`
- Use em-dash (—) for missing values, not empty strings or "N/A"
- Wrap date/number parsing in try-catch blocks
- Handle both singular and plural response shapes
- Test with empty arrays, null values, missing fields

## File Structure

```
src/
  format.js   # All formatter functions + helpers
```

Export all formatters from a single module for easy import in commands.
