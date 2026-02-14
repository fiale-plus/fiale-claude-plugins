---
name: phase1-auth
description: Extract Chrome cookies and auth tokens for a web service
---

# Phase 1: Authentication Extraction

Extract Chrome cookies and auth tokens from the Chrome cookie database to enable authenticated API requests.

## Overview

Chrome stores cookies in an encrypted SQLite database. This guide covers decryption on macOS using the Safe Storage key from the system Keychain.

## Chrome Cookie Database Location

```
~/Library/Application Support/Google/Chrome/<profile>/Cookies
```

Profiles: `Default`, `Profile 1`, `Profile 2`, etc.

## Implementation Steps

### 1. Copy Database to Temporary Location

**Critical**: Copy the DB to avoid WAL (Write-Ahead Logging) lock conflicts with running Chrome:

```javascript
import fs from 'fs/promises';
import path from 'path';
import os from 'os';

const cookieDbPath = path.join(
  os.homedir(),
  'Library/Application Support/Google/Chrome/Default/Cookies'
);

const tmpPath = path.join(os.tmpdir(), `cookies-${Date.now()}.db`);

// Copy main DB and WAL files
await fs.copyFile(cookieDbPath, tmpPath);

const walPath = `${cookieDbPath}-wal`;
const shmPath = `${cookieDbPath}-shm`;

if (await fs.access(walPath).then(() => true).catch(() => false)) {
  await fs.copyFile(walPath, `${tmpPath}-wal`);
}
if (await fs.access(shmPath).then(() => true).catch(() => false)) {
  await fs.copyFile(shmPath, `${tmpPath}-shm`);
}
```

### 2. Get Chrome Safe Storage Key from Keychain

```javascript
import { execSync } from 'child_process';

const safStoragePassword = execSync(
  'security find-generic-password -w -s "Chrome Safe Storage" -a "Chrome"',
  { encoding: 'utf8' }
).trim();
```

### 3. Derive Decryption Key with PBKDF2

Chrome uses PBKDF2 with these parameters:
- Password: Chrome Safe Storage password from Keychain
- Salt: `'saltysalt'` (literal string)
- Iterations: 1003
- Key length: 16 bytes (128 bits)
- Hash: SHA-1

```javascript
import { pbkdf2Sync } from 'crypto';

const key = pbkdf2Sync(
  safStoragePassword,
  'saltysalt',
  1003,
  16,
  'sha1'
);
```

### 4. Query Cookies for Target Domain

```javascript
import Database from 'better-sqlite3';

const db = new Database(tmpPath, { readonly: true });

// Build domain variants for matching
const domainVariants = [
  '.service.com',
  'service.com',
  '.www.service.com'
];

const cookies = db.prepare(`
  SELECT name, encrypted_value, host_key
  FROM cookies
  WHERE host_key IN (${domainVariants.map(() => '?').join(',')})
`).all(...domainVariants);
```

### 5. Decrypt Cookie Values

Chrome cookie encryption:
- Prefix: `v10` (3 bytes) for encrypted values
- Chrome 130+ (DB version >= 24): additional 32-byte domain hash prefix
- Encryption: AES-128-CBC with IV of 16 spaces (`' '.repeat(16)`)

```javascript
import { createDecipheriv } from 'crypto';

function decryptCookie(encryptedValue, key, dbVersion) {
  if (!encryptedValue.toString().startsWith('v10')) {
    return encryptedValue.toString(); // Already plaintext
  }

  let encrypted = encryptedValue.slice(3); // Remove 'v10' prefix

  // Chrome 130+ (DB version >= 24) has 32-byte domain hash
  if (dbVersion >= 24) {
    encrypted = encrypted.slice(32);
  }

  const iv = Buffer.from(' '.repeat(16));
  const decipher = createDecipheriv('aes-128-cbc', key, iv);
  decipher.setAutoPadding(false);

  let decrypted = Buffer.concat([
    decipher.update(encrypted),
    decipher.final()
  ]);

  // Remove PKCS7 padding
  const padding = decrypted[decrypted.length - 1];
  decrypted = decrypted.slice(0, -padding);

  return decrypted.toString('utf8');
}

// Get DB version
const { user_version: dbVersion } = db.prepare('PRAGMA user_version').get();
```

### 6. Build Cookie String and Extract Auth Token

```javascript
const cookieString = cookies
  .map(c => `${c.name}=${decryptCookie(c.encrypted_value, key, dbVersion)}`)
  .join('; ');

// Look for auth token - check known cookie names first
const knownAuthCookies = ['token', 'auth_token', 'access_token', 'jwt'];
let token = null;

for (const c of cookies) {
  const value = decryptCookie(c.encrypted_value, key, dbVersion);

  if (knownAuthCookies.includes(c.name.toLowerCase())) {
    token = value;
    break;
  }

  // Check for JWT pattern (3 dot-separated base64 segments)
  if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value)) {
    token = value;
    break;
  }
}

return { token, cookieString };
```

### 7. Cleanup and Security

```javascript
// Always clean up in finally block
try {
  // ... extraction logic
} finally {
  db.close();
  await fs.unlink(tmpPath).catch(() => {});
  await fs.unlink(`${tmpPath}-wal`).catch(() => {});
  await fs.unlink(`${tmpPath}-shm`).catch(() => {});
}

// If caching credentials, use restrictive permissions
await fs.writeFile(
  cachePath,
  JSON.stringify({ token, cookieString }),
  { mode: 0o600 } // Owner read/write only
);
```

## Return Format

```javascript
{
  token: 'eyJhbGciOiJIUzI1NiIs...', // JWT or auth token
  cookieString: 'session=abc123; user_id=456; token=xyz789'
}
```

## Error Handling

- **DB locked**: Ensure Chrome is closed or copy succeeded
- **Keychain access denied**: User must grant Terminal/app access to Keychain
- **No cookies found**: Check domain variants, verify user is logged in
- **Decryption fails**: Verify DB version detection, check for Chrome updates
