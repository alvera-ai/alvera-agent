# Bootstrap (once per session)

Before any resource work, collect these in a single prompt:

1. **Tenant slug** — the customer's tenant identifier in Alvera.
2. **API key** (`X-API-Key`) — used only for this session, not written to disk.
3. **Base URL** — default `https://admin.alvera.ai`. Override only for staging/dev.
4. **Emit `infra.yaml` receipt?** — default yes. The receipt is a
   human-readable record of what got created.

## Connectivity check

```ts
import { createPlatformApi } from '@alvera-ai/platform-sdk';

const api = createPlatformApi({ baseUrl, apiKey });
await api.ping();
```

If `ping` throws, stop. Tell the user the API is unreachable. Do not
proceed to resource elicitation.

## Datalake selection

Most resources are scoped to a datalake. List the tenant's datalakes:

```ts
const { data: datalakes } = await api.datalakes.list(tenantSlug);
```

- **Zero datalakes** → refuse:
  > "This tenant has no datalakes provisioned. A datalake must exist
  > before resources can be added — ask your Alvera admin to provision one."
- **One datalake** → use it automatically, tell the user.
- **More than one** → ask the user which to operate on. Remember the
  choice for the rest of the session.

## State to retain for the session

- `tenantSlug`
- `datalakeSlug`, `datalakeId`
- `baseUrl`
- the `api` client instance
- whether the YAML receipt is enabled
- the path to the receipt file (default `./infra.yaml`)

Never persist the API key beyond the in-memory `api` client.
