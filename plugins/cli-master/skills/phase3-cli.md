---
name: phase3-cli
description: Build the CLI entry point with parseArgs and command routing
---

# Phase 3: CLI Entry Point

Build the command-line interface with argument parsing, command routing, and output formatting.

## Overview

Create a Node.js CLI that routes commands to API functions, handles errors gracefully, and outputs clean results to stdout while logging diagnostics to stderr.

## Implementation Steps

### 1. Shebang and Imports

```javascript
#!/usr/bin/env node

import { parseArgs } from 'node:util';
import { error } from './utils.js';
```

Make executable:
```bash
chmod +x src/cli.js
```

### 2. Help Documentation

```javascript
const HELP = `
service-cli - Command-line interface for Service

USAGE
  service-cli <command> [options]

COMMANDS
  orders [--limit N]           List recent orders
  order <id>                   Show order details
  search <query> [--lat --lon] Search for items
  favorites                    List favorites
  add-favorite <id>            Add item to favorites
  cancel <order-id>            Cancel an order

OPTIONS
  --json                       Output as JSON
  --profile <name>             Chrome profile (default: Default)
  --timeout <ms>               Request timeout (default: 30000)
  --help, -h                   Show this help

EXAMPLES
  service-cli orders --limit 10
  service-cli order abc123 --json
  service-cli search "pizza" --lat 60.1699 --lon 24.9384
  service-cli add-favorite xyz789
  service-cli cancel abc123

AUTHENTICATION
  Requires Chrome session cookies. Log in to service.com in Chrome first.
`;
```

### 3. Argument Parsing

```javascript
const { values, positionals } = parseArgs({
  options: {
    help: { type: 'boolean', short: 'h' },
    json: { type: 'boolean' },
    profile: { type: 'string', default: 'Default' },
    timeout: { type: 'string', default: '30000' },
    limit: { type: 'string' },
    lat: { type: 'string' },
    lon: { type: 'string' }
  },
  allowPositionals: true,
  strict: false
});

if (values.help || positionals.length === 0) {
  console.log(HELP);
  process.exit(0);
}

const command = positionals[0];
const args = positionals.slice(1);
```

### 4. Error Helper

```javascript
// utils.js
export function error(message) {
  console.error(`service-cli: ${message}`);
  process.exit(1);
}
```

### 5. Command Routing with Lazy Imports

```javascript
try {
  switch (command) {
    case 'orders': {
      // Lazy import API client
      const { getOrders } = await import('./api.js');
      const { formatOrders } = await import('./format.js');

      const limit = values.limit ? parseInt(values.limit) : 20;
      const response = await getOrders({ limit });
      const formatted = formatOrders(response);

      if (values.json) {
        console.log(JSON.stringify(formatted, null, 2));
      } else {
        formatted.forEach(order => {
          console.log(`${order.id}\t${order.status}\t${order.total}\t${order.items} items`);
        });
      }
      break;
    }

    case 'order': {
      if (args.length === 0) {
        error('Order ID required. Usage: service-cli order <id>');
      }

      const { getOrder } = await import('./api.js');
      const { formatOrder } = await import('./format.js');

      const orderId = args[0];
      const order = await getOrder(orderId);
      const formatted = formatOrder(order);

      if (values.json) {
        console.log(JSON.stringify(formatted, null, 2));
      } else {
        console.log(`Order ${formatted.id}`);
        console.log(`Status: ${formatted.status}`);
        console.log(`Total: ${formatted.total}`);
        console.log(`Items: ${formatted.items}`);
        console.log(`Created: ${formatted.createdAt}`);
      }
      break;
    }

    case 'search': {
      if (args.length === 0) {
        error('Search query required. Usage: service-cli search <query>');
      }

      const { search } = await import('./api.js');

      const query = args[0];
      const lat = values.lat;
      const lon = values.lon;

      if (!lat || !lon) {
        error('Location required. Usage: service-cli search <query> --lat 60.1699 --lon 24.9384');
      }

      const results = await search({
        query,
        lat: parseFloat(lat),
        lon: parseFloat(lon)
      });

      if (values.json) {
        console.log(JSON.stringify(results, null, 2));
      } else {
        results.data.forEach(item => {
          console.log(`${item.id}\t${item.name}\t${item.price}`);
        });
      }
      break;
    }

    case 'favorites': {
      const { getFavorites } = await import('./api.js');

      const favorites = await getFavorites();

      if (values.json) {
        console.log(JSON.stringify(favorites, null, 2));
      } else {
        favorites.data.forEach(item => {
          console.log(`${item.id}\t${item.name}`);
        });
      }
      break;
    }

    case 'add-favorite': {
      if (args.length === 0) {
        error('Item ID required. Usage: service-cli add-favorite <id>');
      }

      const { addFavorite } = await import('./api.js');

      const itemId = args[0];
      await addFavorite(itemId);

      console.error('Added to favorites');
      break;
    }

    case 'cancel': {
      if (args.length === 0) {
        error('Order ID required. Usage: service-cli cancel <order-id>');
      }

      const { cancelOrder } = await import('./api.js');

      const orderId = args[0];
      await cancelOrder(orderId);

      console.error(`Cancelled order ${orderId}`);
      break;
    }

    default:
      error(`Unknown command: ${command}\n\n${HELP}`);
  }
} catch (err) {
  error(err.message);
}
```

### 6. Output Conventions

**stdout for content, stderr for diagnostics:**

```javascript
// Good: content to stdout
console.log(JSON.stringify(data));
console.log(`${order.id}\t${order.status}`);

// Good: diagnostics to stderr
console.error('Added to favorites');
console.error('Fetching orders...');

// Bad: mixing content and diagnostics
console.log('Success! Order cancelled'); // Should be stderr
```

### 7. Validation Helpers

```javascript
function validateRequired(value, name, usage) {
  if (!value) {
    error(`${name} required. Usage: ${usage}`);
  }
}

function validateCoordinates(lat, lon) {
  if (!lat || !lon) {
    error('Location required. Use --lat and --lon');
  }
  const latNum = parseFloat(lat);
  const lonNum = parseFloat(lon);
  if (isNaN(latNum) || isNaN(lonNum)) {
    error('Invalid coordinates. Must be numbers.');
  }
  if (latNum < -90 || latNum > 90) {
    error('Latitude must be between -90 and 90');
  }
  if (lonNum < -180 || lonNum > 180) {
    error('Longitude must be between -180 and 180');
  }
  return { lat: latNum, lon: lonNum };
}

// Usage
case 'search': {
  validateRequired(args[0], 'Search query', 'service-cli search <query>');
  const coords = validateCoordinates(values.lat, values.lon);
  // ...
}
```

## CLI Checklist

- [ ] Shebang `#!/usr/bin/env node` at top
- [ ] Made executable with `chmod +x`
- [ ] HELP constant with usage, commands, options, examples
- [ ] `parseArgs` with `allowPositionals: true`
- [ ] Standard options: --json, --profile, --timeout, --help
- [ ] Command routing via switch on positionals[0]
- [ ] Lazy dynamic imports inside each case
- [ ] Error helper with service name prefix
- [ ] stdout for content, stderr for diagnostics
- [ ] Validate required args per command
- [ ] Handle --json flag for structured output
- [ ] Catch-all error handler at top level
- [ ] Test with `node src/cli.js --help`

## Testing

```bash
# Test help
node src/cli.js --help

# Test commands
node src/cli.js orders --limit 5
node src/cli.js order abc123 --json
node src/cli.js search "pizza" --lat 60.1699 --lon 24.9384

# Test error handling
node src/cli.js order              # Missing ID
node src/cli.js search "pizza"     # Missing location
node src/cli.js invalid-command    # Unknown command
```

## Example Full CLI

```javascript
#!/usr/bin/env node

import { parseArgs } from 'node:util';

const HELP = `
myservice - Example service CLI

USAGE
  myservice <command> [options]

COMMANDS
  orders                  List recent orders
  order <id>              Show order details

OPTIONS
  --json                  Output as JSON
  --help                  Show help
`;

function error(msg) {
  console.error(`myservice: ${msg}`);
  process.exit(1);
}

const { values, positionals } = parseArgs({
  options: {
    help: { type: 'boolean' },
    json: { type: 'boolean' }
  },
  allowPositionals: true
});

if (values.help || !positionals[0]) {
  console.log(HELP);
  process.exit(0);
}

try {
  const command = positionals[0];

  switch (command) {
    case 'orders': {
      const { getOrders } = await import('./api.js');
      const orders = await getOrders();
      console.log(values.json ? JSON.stringify(orders) : orders);
      break;
    }
    default:
      error(`Unknown command: ${command}`);
  }
} catch (err) {
  error(err.message);
}
```
