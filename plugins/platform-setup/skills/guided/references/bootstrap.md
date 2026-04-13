# Bootstrap (once per session)

Before any resource work, collect these in a single prompt:

1. **Email** — the user's Alvera login email.
2. **Password** — their Alvera login password. Treat as a secret (see
   `guardrails.md`): never log, never echo, never write to disk.
3. **Tenant slug** — the tenant they want to operate on (the session is
   tenant-scoped).
4. **Base URL** — default `https://admin.alvera.ai`. Override only for
   staging/dev.
5. **Emit `infra.yaml` receipt?** — default yes. Human-readable record of
   what got created.

## Authenticate

```ts
import { createSession, createPlatformApi } from '@alvera-ai/platform-sdk';

const session = await createSession({
  baseUrl,
  email,
  password,
  tenantSlug,
});

const api = createPlatformApi({
  baseUrl,
  sessionToken: session.sessionToken,
});
```

- Discard `email` / `password` from memory immediately after `createSession`
  returns. Hold only `session.sessionToken` and `session.expiresAt`.
- If `createSession` throws (e.g. 401), surface the error verbatim and
  stop. Do not retry without asking the user — credentials may be wrong.
- `session.expiresAt` is ISO-8601 (default 24h). For long sessions, check
  it before each create and re-authenticate if expired.

## Connectivity check

```ts
await api.ping();
```

If `ping` throws, stop. Tell the user the API is unreachable.

## Datalake selection

Most resources are scoped to a datalake. List them:

```ts
const { data: datalakes } = await api.datalakes.list(tenantSlug);
```

- **Zero datalakes** → refuse:
  > "This tenant has no datalakes provisioned. A datalake must exist
  > before resources can be added — ask your Alvera admin to provision one."
- **One** → use it automatically, tell the user.
- **More than one** → ask which to operate on. Remember for the session.

## State to retain for the session

- `tenantSlug`
- `datalakeSlug`, `datalakeId`
- `baseUrl`
- the `api` client instance
- `sessionToken`, `expiresAt`
- whether the YAML receipt is enabled
- the path to the receipt file (default `./infra.yaml`)

**Never persist** the email, password, or session token to disk. They live
only in process memory for the duration of the conversation.

## Cleanup (optional but recommended)

When the user signals they're done:

```ts
import { revokeSession } from '@alvera-ai/platform-sdk';
await revokeSession();
```

This invalidates the token immediately rather than waiting for `expiresAt`.
