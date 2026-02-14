/**
 * Format Avanza API responses as markdown tables or JSON.
 */

export function formatOverview(data, { json = false } = {}) {
  if (json) return JSON.stringify(data, null, 2);

  const lines = ['# Portfolio Overview', ''];

  const totalValue = data.totalValue || data.totalOwnCapital;
  const dailyChange = data.totalChangeDuringPeriod || data.changeToday;
  const dailyPct = data.totalChangeDuringPeriodPercent || data.changeTodayPercent;

  if (totalValue != null) lines.push(`**Total Value:** ${formatSEK(totalValue)}`);
  if (dailyChange != null) lines.push(`**Daily Change:** ${formatSEK(dailyChange)} (${formatPct(dailyPct)})`);

  // Account summaries
  const accounts = data.accounts || data.accountViews || [];
  if (accounts.length) {
    lines.push('');
    lines.push('## Accounts');
    lines.push('');
    lines.push('| Account | Type | Value |');
    lines.push('|---------|------|-------|');
    for (const a of accounts) {
      const name = a.name || a.accountName || '—';
      const type = a.accountType || a.type || '—';
      const value = formatSEK(a.ownCapital || a.totalValue || a.value);
      lines.push(`| ${name} | ${type} | ${value} |`);
    }
  }

  return lines.join('\n');
}

export function formatAccounts(data, { json = false } = {}) {
  if (json) return JSON.stringify(data, null, 2);

  const accounts = extractList(data);
  if (!accounts.length) return 'No accounts found.';

  const lines = ['# Accounts', ''];
  lines.push('| Account | Type | Number | Value |');
  lines.push('|---------|------|--------|-------|');

  for (const a of accounts) {
    const name = a.name || a.accountName || '—';
    const type = a.accountType || a.type || '—';
    const number = a.accountId || a.accountNumber || '—';
    const value = formatSEK(a.ownCapital || a.totalValue || a.value);
    lines.push(`| ${name} | ${type} | \`${number}\` | ${value} |`);
  }

  return lines.join('\n');
}

export function formatHoldings(data, { json = false } = {}) {
  if (json) return JSON.stringify(data, null, 2);

  const positions = extractPositions(data);
  if (!positions.length) return 'No holdings found.';

  const lines = ['# Holdings', ''];
  lines.push('| Instrument | Qty | Avg Price | Price | Change | Value |');
  lines.push('|------------|-----|-----------|-------|--------|-------|');

  for (const p of positions) {
    const name = p.name || p.instrumentName || '—';
    const qty = p.volume || p.quantity || '—';
    const avg = formatSEK(p.acquiredPrice || p.averageAcquiredPrice);
    const price = formatSEK(p.lastPrice || p.currentPrice);
    const change = formatPct(p.changePercent || p.todayChangePercent);
    const value = formatSEK(p.value || p.marketValue);
    lines.push(`| ${name} | ${qty} | ${avg} | ${price} | ${change} | ${value} |`);
  }

  return lines.join('\n');
}

export function formatTransactions(data, { json = false } = {}) {
  if (json) return JSON.stringify(data, null, 2);

  const txns = extractList(data);
  if (!txns.length) return 'No transactions found.';

  const lines = ['# Transactions', ''];
  lines.push('| Date | Type | Instrument | Qty | Price | Amount |');
  lines.push('|------|------|------------|-----|-------|--------|');

  for (const t of txns) {
    const date = formatDate(t.date || t.transactionDate || t.settledDate);
    const type = t.transactionType || t.type || '—';
    const name = t.description || t.instrumentName || t.name || '—';
    const qty = t.volume || t.quantity || '—';
    const price = formatSEK(t.price);
    const amount = formatSEK(t.amount || t.total);
    lines.push(`| ${date} | ${type} | ${name} | ${qty} | ${price} | ${amount} |`);
  }

  return lines.join('\n');
}

// --- Helpers ---

function extractList(data) {
  if (Array.isArray(data)) return data;
  if (data.accounts) return data.accounts;
  if (data.transactions) return data.transactions;
  if (data.results) return data.results;
  if (data.items) return data.items;
  return [];
}

function extractPositions(data) {
  if (Array.isArray(data)) return data;
  if (data.positions) return data.positions;
  if (data.instrumentPositions) {
    // Avanza nests positions by instrument type
    return data.instrumentPositions.flatMap(g => g.positions || []);
  }
  if (data.items) return data.items;
  return [];
}

function formatDate(dateStr) {
  if (!dateStr) return '—';
  try {
    const d = new Date(dateStr);
    return d.toLocaleDateString('sv-SE');
  } catch {
    return dateStr;
  }
}

function formatSEK(value) {
  if (value == null) return '—';
  const num = Number(value);
  if (isNaN(num)) return String(value);
  return num.toLocaleString('sv-SE', { style: 'currency', currency: 'SEK', maximumFractionDigits: 2 });
}

function formatPct(value) {
  if (value == null) return '—';
  const num = Number(value);
  if (isNaN(num)) return String(value);
  const sign = num >= 0 ? '+' : '';
  return `${sign}${num.toFixed(2)}%`;
}
