# CLI cheat sheet

CLI: `alvera`, shipped by
[`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk).

```bash
npx -p @alvera-ai/platform-sdk alvera <command>   # zero-install
alvera <command>                                    # if installed globally
```

## Global options

| Flag                 | Purpose                                         |
|----------------------|-------------------------------------------------|
| `--profile <name>`   | Config profile (default `default`).             |

Env var overrides: `ALVERA_PROFILE`, `ALVERA_BASE_URL`, `ALVERA_TENANT`,
`ALVERA_EMAIL`, `ALVERA_SESSION_TOKEN`.

## Auth & session

```bash
alvera configure                       # interactive: base URL, tenant, email
alvera login                           # exchange creds → session token (user runs this)
alvera logout                          # revoke + clear local credentials
alvera whoami                          # print resolved profile + token presence
alvera ping                            # health check
alvera sessions-verify                 # verify session token via API
```

The skill **does not invoke `login`**. The user runs it in their own
terminal.

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

# Generic tables
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

# Connected apps
alvera connected-apps list        <datalake> [tenant]
alvera connected-apps get         <datalake> <id> [tenant]
alvera connected-apps create      <datalake> [tenant]      --body '<json>' | --body-file <path>
alvera connected-apps update      <datalake> <id> [tenant] --body '<json>' | --body-file <path>
alvera connected-apps sync-routes <datalake> <id> [tenant]

# Data activation clients
alvera data-activation-clients list         <datalake> [tenant]
alvera data-activation-clients get          <datalake> <slug> [tenant]
alvera data-activation-clients create       <datalake> [tenant]      --body '<json>' | --body-file <path>
alvera data-activation-clients update       <datalake> <slug> [tenant] --body '<json>' | --body-file <path>
alvera data-activation-clients delete       <datalake> <slug> [tenant]
alvera data-activation-clients metadata     <datalake> <slug> [tenant]
alvera data-activation-clients run-manually <datalake> <slug> [tenant] [--body '<json>']
alvera data-activation-clients ingest       <datalake> <slug> [tenant]  --body '<json>' | --body-file <path>
alvera data-activation-clients ingest-file  <datalake> <slug> <key> [tenant]
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

# Agentic workflows
alvera workflows list     <datalake> [tenant]
alvera workflows get      <datalake> <id> [tenant]
alvera workflows create   <datalake> [tenant]       --body '<json>' | --body-file <path>
alvera workflows update   <datalake> <id> [tenant]  --body '<json>' | --body-file <path>
alvera workflows delete   <datalake> <id> [tenant]
alvera workflows metadata <datalake> <id> [tenant]
alvera workflows execute  <workflow-slug> [tenant]   --body '<json>' | --body-file <path>
alvera workflows run      <workflow-slug> [tenant]   --body '<json>' | --body-file <path>
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

# MDM
alvera mdm verify <datalake> [tenant]  --body '<json>' | --body-file <path>

# Init (scaffolding)
alvera init connected-app              # generate .env for app integration
alvera init infra-setup                # generate .env for datalake infrastructure
```

## Batch operations (workflows)

Batch operations manage long-running bulk workflow executions:

```bash
alvera workflows batch-logs          <workflow-slug> [tenant]       # list batch runs
alvera workflows batch-log           <workflow-slug> <id> [tenant]  # get batch details
alvera workflows batch-log-start     <workflow-slug> <id> [tenant]  # resume a paused batch
alvera workflows batch-log-stop      <workflow-slug> <id> [tenant]  # pause a running batch
alvera workflows batch-log-refresh   <workflow-slug> <id> [tenant]  # refresh batch status
```

Use `batch-logs` to monitor bulk `run` executions. Each batch has a
lifecycle: `running` → `completed` | `stopped` | `failed`. Use
`batch-log-stop` to pause a problematic batch, `batch-log-start` to
resume after fixing.

## Slug vs ID

Some resources use slug for execution commands and ID for mutation commands:

| Resource | Execution (slug) | Mutation (ID) |
|----------|-----------------|---------------|
| Workflows | `run`, `execute`, `workflow-logs`, `batch-logs` | `update`, `delete`, `get` |
| DACs | `run-manually`, `ingest`, `ingest-file`, `logs` | `update`, `delete` |
| Interop | `run`, `metadata` | `update`, `delete` |

`create` returns both — store both values.

## Output and errors

- Stdout: pretty-printed JSON.
- Stderr: prompts, status messages, errors (prefixed `alvera: `).
- Exit code: `0` on success, `1` on any failure.

Surface stderr verbatim on non-zero exit.

## Body sourcing

```bash
alvera tools create --body '{"name":"X","intent":"data_exchange",...}'
alvera ai-agents create acme-health --body-file ./agent.json
cat <<'JSON' | alvera generic-tables create acme-health --body-file -
{"title":"Patients","columns":[...]}
JSON
```

Prefer `--body-file` for payloads with nested objects, embedded quotes,
or secrets.
