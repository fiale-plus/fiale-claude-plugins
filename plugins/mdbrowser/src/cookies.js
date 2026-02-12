import { execSync } from 'node:child_process';
import { copyFileSync, unlinkSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pbkdf2Sync, createDecipheriv } from 'node:crypto';

export async function getChromeCoookies(url, { profile = 'Default' } = {}) {
  if (process.platform !== 'darwin') {
    throw new Error(
      'Chrome cookie extraction is only supported on macOS.\n' +
      'Linux support requires decrypting with GNOME Keyring or KWallet.\n' +
      'Windows support requires DPAPI decryption.'
    );
  }

  let Database;
  try {
    Database = (await import('better-sqlite3')).default;
  } catch {
    throw new Error(
      'Chrome cookie extraction requires better-sqlite3.\n' +
      'Install it with: npm install better-sqlite3'
    );
  }

  const { hostname } = new URL(url);
  const domains = buildDomainVariants(hostname);

  const cookiesPath = join(
    process.env.HOME,
    'Library/Application Support/Google/Chrome',
    profile,
    'Cookies'
  );

  if (!existsSync(cookiesPath)) {
    throw new Error(
      `Chrome Cookies DB not found at: ${cookiesPath}\n` +
      `Check your profile name (current: "${profile}"). ` +
      `List profiles: ls ~/Library/Application\\ Support/Google/Chrome/`
    );
  }

  // Copy to avoid WAL lock conflicts with running Chrome
  const tmpPath = join(tmpdir(), `mdbrowser-cookies-${Date.now()}.db`);
  copyFileSync(cookiesPath, tmpPath);

  // Also copy WAL and SHM if they exist
  for (const ext of ['-wal', '-shm']) {
    const src = cookiesPath + ext;
    if (existsSync(src)) {
      copyFileSync(src, tmpPath + ext);
    }
  }

  try {
    const key = getDecryptionKey();
    const db = new Database(tmpPath, { readonly: true });

    // Chrome 130+ (DB version ≥ 24) prepends a 32-byte domain hash before encryption
    const meta = db.prepare("SELECT value FROM meta WHERE key = 'version'").get();
    const dbVersion = meta ? Number(meta.value) : 0;

    const placeholders = domains.map(() => '?').join(', ');
    const rows = db.prepare(
      `SELECT host_key, name, encrypted_value, path, is_secure, is_httponly
       FROM cookies
       WHERE host_key IN (${placeholders})`
    ).all(...domains);

    db.close();

    const cookies = rows
      .map(row => {
        const value = decryptCookieValue(row.encrypted_value, key, dbVersion);
        return value ? `${row.name}=${value}` : null;
      })
      .filter(Boolean);

    return cookies.join('; ');
  } finally {
    for (const ext of ['', '-wal', '-shm']) {
      const f = tmpPath + ext;
      if (existsSync(f)) unlinkSync(f);
    }
  }
}

function buildDomainVariants(hostname) {
  // e.g. "github.com" → [".github.com", "github.com"]
  // "mail.google.com" → [".mail.google.com", "mail.google.com", ".google.com"]
  const variants = [`.${hostname}`, hostname];
  const parts = hostname.split('.');
  if (parts.length > 2) {
    const parent = parts.slice(1).join('.');
    variants.push(`.${parent}`);
  }
  return variants;
}

function getDecryptionKey() {
  const chromePassword = execSync(
    'security find-generic-password -w -s "Chrome Safe Storage" -a "Chrome"',
    { encoding: 'utf8' }
  ).trim();

  return pbkdf2Sync(chromePassword, 'saltysalt', 1003, 16, 'sha1');
}

function decryptCookieValue(encrypted, key, dbVersion) {
  if (!encrypted || encrypted.length === 0) return '';

  // Chrome v10 encrypted cookies on macOS: "v10" prefix + AES-128-CBC
  const buf = Buffer.isBuffer(encrypted) ? encrypted : Buffer.from(encrypted);

  if (buf.length < 3) return '';

  // Check for v10 prefix
  if (buf[0] === 0x76 && buf[1] === 0x31 && buf[2] === 0x30) {
    const ciphertext = buf.subarray(3);
    if (ciphertext.length === 0) return '';

    try {
      const iv = Buffer.alloc(16, 0x20); // 16 bytes of space (0x20)
      const decipher = createDecipheriv('aes-128-cbc', key, iv);
      let decrypted = decipher.update(ciphertext);
      decrypted = Buffer.concat([decrypted, decipher.final()]);

      // Chrome 130+ (DB version ≥ 24) prepends 32-byte SHA256 domain hash
      if (dbVersion >= 24) {
        decrypted = decrypted.subarray(32);
      }

      return decrypted.toString('utf8');
    } catch {
      return null; // skip cookies that fail to decrypt
    }
  }

  // Unencrypted cookie (rare)
  return buf.toString('utf8');
}
