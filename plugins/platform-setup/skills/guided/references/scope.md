# Scope

## In scope

| Resource                | Operations                                  |
|-------------------------|---------------------------------------------|
| `datalakes`             | list, get, create, upload-link              |
| `dataSources`           | list, create, update                        |
| `tools`                 | list, get, create, update, delete           |
| `actionStatusUpdaters`  | list, create, update                        |
| `aiAgents`              | list, get, create, update, delete           |
| `connectedApps`         | list, get, create, update, syncRoutes       |
| `agenticWorkflows`      | list, get, create, update, delete, execute, run |
| `interopContracts`      | list, get, create, update, delete, run      |
| `dataActivationClients` | list, get, create, update, delete, run-manually |
| `ping`                  | health check                                |

Generic tables (custom datasets) are **not** handled by this skill —
they live in `custom-dataset-creation` because the flow needs a
compliance gate and column-profiling steps that don't fit the generic
resource loop.

Workflow runtime ops (batch-logs, workflow-logs, download) are **read-
only monitoring** — the skill offers them when the user asks "what
happened to my last run?" but does not drive them proactively. DAC
runtime ops (ingest, ingest-file) live in the `DAC-upload` skill.

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
