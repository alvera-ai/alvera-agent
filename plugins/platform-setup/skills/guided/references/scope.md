# Scope

## In scope

| Resource                | Operations                                  |
|-------------------------|---------------------------------------------|
| `datalakes`             | list, get, create                           |
| `dataSources`           | list, create, update                        |
| `tools`                 | list, get, create, update, delete           |
| `genericTables`         | list, create                                |
| `actionStatusUpdaters`  | list, create, update                        |
| `aiAgents`              | list, get, create, update, delete           |
| `connectedApps`         | list, get, create, update, syncRoutes       |
| `ping`                  | health check                                |

Datalake creation is in scope but is sensitive — it takes DB
credentials (four roles × password/host/port/schema/SSL/auth). See
`resources.md` → "Datalake" for elicitation rules and
`guardrails.md` → "Secrets handling" for how creds are sourced.

## Out of scope (refuse)

- Tenant create / delete (admin-only)
- Datalake **delete** / **update** — the API doesn't expose them.
  If the user asks, say so and offer to create a new datalake instead.
- Dataset search, workflow execute, data activation ingest (runtime ops)
- MDM verify
- Connected app **page management** — `connected-apps resolve-page` and
  `connected-apps update-message-tracking` are runtime page rendering,
  not provisioning. The CRUD + `sync-routes` operations on connected app
  *resources* are in scope; the page-level endpoints are not.
- Anything touching another tenant
- Anything not listed in "In scope"

## Refusal language

When asked for an out-of-scope operation, reply verbatim:

> "I can only set up resources within an existing tenant + datalake. For
> tenant or datalake provisioning, contact your Alvera admin."

If the user pushes back, do not negotiate. Do not invent workarounds.
Do not invoke the CLI for operations not listed in "In scope".
