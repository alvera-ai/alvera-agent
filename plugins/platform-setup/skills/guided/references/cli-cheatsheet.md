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
```

The skill **does not invoke `login`**. The user runs it in their own
terminal so the password is never visible to the model. See
`bootstrap.md`.

## Resource commands

Tenant positional arg is optional when the profile has a default
tenant. All `create` / `update` commands take exactly one of
`--body '<json>'` or `--body-file <path>` (use `-` for stdin).

```bash
# Datalakes
alvera datalakes list        [tenant]
alvera datalakes get         <id> [tenant]
alvera datalakes create      [tenant]                          --body-file <path>
alvera datalakes upload-link <datalake> <filename> [tenant]    --content-type text/csv|application/x-ndjson
# Prefer --body-file over --body '<json>' for datalake create — the payload
# contains DB passwords. See resources.md → "Datalake" for the three
# credential-sourcing patterns (env vars, .env, one-shot literal).
# upload-link returns { url, key, expires_in }. Drives the DAC-upload skill;
# pair it with `data-activation-clients ingest-file <dac> <key>` (below).

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

# Data activation clients — runtime ingest only (CRUD not on public API).
# `ingest-file` triggers processing of a file previously uploaded via
# `datalakes upload-link` (above). Drives the `DAC-upload` skill — don't
# invoke directly from `guided`.
alvera data-activation-clients ingest      <slug> [tenant]      --body '<json>' | --body-file <path>
alvera data-activation-clients ingest-file <slug> <key> [tenant]
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
