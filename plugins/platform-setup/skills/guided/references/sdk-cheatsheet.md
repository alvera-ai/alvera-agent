# SDK cheat sheet

Package: [`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk)
(>= 0.2.0 — session-based auth)

```ts
import { createSession, createPlatformApi, revokeSession } from '@alvera-ai/platform-sdk';

const baseUrl = 'https://admin.alvera.ai';

// Auth: exchange credentials for a session token
const session = await createSession({
  baseUrl,
  email: '<user email>',
  password: '<user password>',   // discard immediately after this call
  tenantSlug: '<tenant slug>',
  // expiresIn: 3600,            // optional, default 86400 (24h), max 2592000 (30d)
});

// Build the API client
const api = createPlatformApi({
  baseUrl,
  sessionToken: session.sessionToken,
});

// Use it...
// On done:
await revokeSession();
```

`session.expiresAt` is ISO-8601 — re-authenticate if expired before
long-running work.

## Methods

```ts
// Health
await api.ping();

// Datalakes (read-only)
await api.datalakes.list(tenantSlug);
await api.datalakes.get(tenantSlug, id);

// Data sources
await api.dataSources.list(tenantSlug, datalakeSlug);
await api.dataSources.create(tenantSlug, datalakeSlug, body);
await api.dataSources.update(tenantSlug, datalakeSlug, id, body);

// Tools
await api.tools.list(tenantSlug);
await api.tools.get(tenantSlug, id);
await api.tools.create(tenantSlug, body);
await api.tools.update(tenantSlug, id, body);
await api.tools.delete(tenantSlug, id);

// Generic tables
await api.genericTables.list(tenantSlug, datalakeSlug);
await api.genericTables.create(tenantSlug, datalakeSlug, body);

// Action status updaters
await api.actionStatusUpdaters.list(tenantSlug);
await api.actionStatusUpdaters.create(tenantSlug, body);
await api.actionStatusUpdaters.update(tenantSlug, id, body);

// AI agents
await api.aiAgents.list(tenantSlug, datalakeSlug);
await api.aiAgents.get(tenantSlug, datalakeSlug, id);
await api.aiAgents.create(tenantSlug, datalakeSlug, body);
await api.aiAgents.update(tenantSlug, datalakeSlug, id, body);
await api.aiAgents.delete(tenantSlug, datalakeSlug, id);
```

## Notes

- All methods return `{ data, response, ... }` from `@hey-api/client-fetch`.
  Destructure `data` for the typed payload.
- All methods throw on non-2xx (`throwOnError: true`). Wrap in try/catch
  and surface the error message verbatim.
- Auth is **session-based** (Bearer token). `createSession` exchanges
  credentials for a token; the token expires (default 24h). Use
  `revokeSession()` to invalidate explicitly.
