# CLI cheat sheet

CLI: `alvera`, shipped by
[`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk).
Always use the latest published version.

```bash
# Zero-install
npx -p @alvera-ai/platform-sdk alvera <command>

# Or install globally
npm install -g @alvera-ai/platform-sdk
alvera <command>
```

The bare `alvera <command>` form is used below — substitute the `npx`
prefix at run time.

## Global options

| Flag                 | Purpose                                         |
|----------------------|-------------------------------------------------|
| `--profile <name>`   | Config profile (default `default`).             |

Env var overrides (take precedence over file values): `ALVERA_PROFILE`,
`ALVERA_BASE_URL`, `ALVERA_TENANT`, `ALVERA_EMAIL`, `ALVERA_PASSWORD`,
`ALVERA_SESSION_TOKEN`.

## Auth & session

```bash
alvera configure                       # interactive: base URL, tenant, email
alvera login                           # exchange creds → session token (user runs this)
       [--email <e>] [--tenant <slug>] [--base-url <url>] [--expires-in <seconds>]
alvera logout                          # revoke + clear local credentials
alvera whoami                          # print resolved profile + token presence
alvera ping                            # health check
alvera sessions-verify                 # verify session token via API
```

The skill **does not invoke `login`**. The user runs it in their own
terminal so the password is never visible to the model. See
`bootstrap.md`.

## Resource commands

Tenant positional arg is optional when the profile has a default
tenant. All `create` / `update` commands take exactly one of
`--body '<json>'` or `--body-file <path>` (use `-` for stdin).

```bash
# Tenants
alvera tenants list

# Datalakes
alvera datalakes list        [tenant]
alvera datalakes get         <id> [tenant]
alvera datalakes create      [tenant]                          --body-file <path>
alvera datalakes metadata    <datalake> [tenant]
alvera datalakes upload-link <datalake> <filename> [tenant]    --content-type text/csv|application/x-ndjson
# Prefer --body-file over --body '<json>' for datalake create — the payload
# contains DB passwords. See resources.md → "Datalake" for the three
# credential-sourcing patterns (env vars, .env, one-shot literal).
# upload-link returns { url, key, expires_in }. Drives the DAC-upload skill;
# pair it with `data-activation-clients ingest-file <datalake> <slug> <key>`.

# Data sources
alvera data-sources list   <datalake> [tenant]
alvera data-sources create <datalake> [tenant]      --body '<json>' | --body-file <path>
alvera data-sources update <datalake> <id> [tenant] --body '<json>' | --body-file <path>

# Tools
alvera tools list   [tenant]
alvera tools get    <id> [tenant]
alvera tools create [tenant]                        --body '<json>' | --body-file <path>
alvera tools update <id> [tenant]                   --body '<json>' | --body-file <path>
alvera tools delete <id> [tenant]

# Generic tables — CLI documented here for completeness, but the flow
# (compliance gate, column profiling, schema proposal) lives in the
# `custom-dataset-creation` skill. Don't drive this from `guided`.
alvera generic-tables list   <datalake> [tenant]
alvera generic-tables create <datalake> [tenant]    --body '<json>' | --body-file <path>

# Action status updaters
alvera action-status-updaters list   [tenant]
alvera action-status-updaters create [tenant]       --body '<json>' | --body-file <path>
alvera action-status-updaters update <id> [tenant]  --body '<json>' | --body-file <path>

# AI agents
alvera ai-agents list   <datalake> [tenant]
alvera ai-agents get    <datalake> <id> [tenant]
alvera ai-agents create <datalake> [tenant]         --body '<json>' | --body-file <path>
alvera ai-agents update <datalake> <id> [tenant]    --body '<json>' | --body-file <path>
alvera ai-agents delete <datalake> <id> [tenant]

# Connected apps (datalake-scoped resource CRUD + sync-routes action).
# The `resolve-page` and `update-message-tracking` subcommands are page
# rendering / runtime — out of scope, do not invoke.
alvera connected-apps list        <datalake> [tenant]
alvera connected-apps get         <datalake> <id> [tenant]
alvera connected-apps create      <datalake> [tenant]      --body '<json>' | --body-file <path>
alvera connected-apps update      <datalake> <id> [tenant] --body '<json>' | --body-file <path>
alvera connected-apps sync-routes <datalake> <id> [tenant]

# Data activation clients — full CRUD + runtime ops.
# CRUD is in `guided` scope; runtime ingest drives the `DAC-upload` skill.
alvera data-activation-clients list         <datalake> [tenant]
alvera data-activation-clients get          <datalake> <slug> [tenant]
alvera data-activation-clients create       <datalake> [tenant]      --body '<json>' | --body-file <path>
alvera data-activation-clients update       <datalake> <slug> [tenant] --body '<json>' | --body-file <path>
alvera data-activation-clients delete       <datalake> <slug> [tenant]
alvera data-activation-clients metadata     <datalake> <slug> [tenant]
alvera data-activation-clients run-manually <datalake> <slug> [tenant] [--body '<json>']
alvera data-activation-clients ingest       <datalake> <slug> [tenant]  --body '<json>' | --body-file <path>
alvera data-activation-clients ingest-file  <datalake> <slug> <key> [tenant]

# Data activation client logs
alvera data-activation-clients logs         <datalake> <slug> [tenant]
alvera data-activation-clients log-get      <datalake> <slug> <id> [tenant]
alvera data-activation-clients log-download <datalake> <slug> <id> [tenant]

# Interoperability contracts (alias: interop)
alvera interop list     <datalake> [tenant]
alvera interop get      <datalake> <slug> [tenant]
alvera interop create   <datalake> [tenant]       --body '<json>' | --body-file <path>
alvera interop update   <datalake> <slug> [tenant] --body '<json>' | --body-file <path>
alvera interop delete   <datalake> <slug> [tenant]
alvera interop metadata <datalake> <slug> [tenant]
alvera interop run      <datalake> <slug> [tenant] --body '<json>' | --body-file <path>

# Agentic workflows — CRUD is datalake-scoped; execute/run are workflow-slug-scoped
alvera workflows list     <datalake> [tenant]
alvera workflows get      <datalake> <id> [tenant]
alvera workflows create   <datalake> [tenant]       --body '<json>' | --body-file <path>
alvera workflows update   <datalake> <id> [tenant]  --body '<json>' | --body-file <path>
alvera workflows delete   <datalake> <id> [tenant]
alvera workflows metadata <datalake> <id> [tenant]
alvera workflows execute  <workflow-slug> [tenant]   --body '<json>' | --body-file <path>
alvera workflows run      <workflow-slug> [tenant]   --body '<json>' | --body-file <path>
# run takes { sql_where_clause, mode: "live"|"dry_run", manual_override? }

# Workflow monitoring — flat command names (not nested subcommands)
alvera workflows batch-logs          <workflow-slug> [tenant]
alvera workflows batch-log           <workflow-slug> <id> [tenant]
alvera workflows batch-log-start     <workflow-slug> <id> [tenant]
alvera workflows batch-log-stop      <workflow-slug> <id> [tenant]
alvera workflows batch-log-refresh   <workflow-slug> <id> [tenant]
alvera workflows workflow-logs       <workflow-slug> [tenant]
alvera workflows workflow-log        <workflow-slug> <id> [tenant]
alvera workflows workflow-log-download <workflow-slug> <id> [tenant]

# Datasets (search + metadata)
alvera datasets search   <dataset> [--datalake-id <id>] [--page <n>] [--page-size <n>]
alvera datasets metadata <dataset-type> [--datalake-id <id>] [--generic-table-id <id>]

# MDM (Master Data Management)
alvera mdm verify <datalake> [tenant]  --body '<json>' | --body-file <path>
```

## Output and errors

- Stdout: pretty-printed JSON of the response payload.
- Stderr: prompts, status messages, and error lines (prefixed with
  `alvera: `).
- Exit code: `0` on success, `1` on any failure (auth, validation,
  network, non-2xx response).

Surface stderr verbatim to the user on any non-zero exit. Do not invent
fallbacks. Do not retry without asking.

## Body sourcing

For anything beyond a tiny inline payload, prefer `--body-file`:

```bash
# inline (small payload)
alvera tools create --body '{"name":"X","intent":"data_exchange",...}'

# from file
alvera ai-agents create acme-health --body-file ./agent.json

# from stdin (handy in scripts / heredocs)
cat <<'JSON' | alvera generic-tables create acme-health --body-file -
{"title":"Patients","columns":[...]}
JSON
```

Inline JSON in a shell can be brittle around quoting; reach for
`--body-file` when the payload has nested objects, embedded quotes, or
secrets (so the value doesn't land in shell history).
