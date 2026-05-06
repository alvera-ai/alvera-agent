# Scope

## In scope

| Resource                | Operations                                  |
|-------------------------|---------------------------------------------|
| `datalakes`             | list, get, create, upload-link              |
| `dataSources`           | list, create, update                        |
| `tools`                 | list, get, create, update, delete           |
| `genericTables`         | list, create (with compliance gate + profiling) |
| `actionStatusUpdaters`  | list, create, update                        |
| `aiAgents`              | list, get, create, update, delete           |
| `connectedApps`         | list, get, create, update, syncRoutes       |
| `agenticWorkflows`      | list, get, create, update, delete, execute, run |
| `interopContracts`      | list, get, create, update, delete, run      |
| `dataActivationClients` | list, get, create, update, delete, run-manually, ingest, ingest-file |
| `datasets`              | search, metadata (read-only monitoring)     |
| `mdm`                   | verify (read-only identity resolution)      |
| `ping`                  | health check                                |

## Out of scope (refuse)

- Tenant create / delete (admin-only)
- Datalake **delete** / **update** — the API doesn't expose them.
  Offer to create a new one instead.
- Connected app **page management** — `connected-apps resolve-page` and
  `connected-apps update-message-tracking` are runtime page rendering,
  not provisioning. CRUD + `sync-routes` on connected app resources are in
  scope; page-level endpoints are not.
- Anything touching another tenant
- Anything not listed in "In scope"

## Refusal language

When asked for an out-of-scope operation, reply verbatim:

> "I can only set up resources within an existing tenant + datalake. For
> tenant or datalake provisioning, contact your Alvera admin."

If the user pushes back, do not negotiate. Do not invent workarounds.
Do not invoke the CLI for operations not listed in "In scope".
