# Guardrails (non-negotiable)

## No silent upsert

Always `list` before `create`. If a name collides with an existing
resource, stop and ask:

> "A `<resource>` named `<name>` already exists (id `<id>`). Do you want
> to (a) update it, (b) pick a different name, or (c) skip?"

Never auto-update on collision. Never auto-rename.

## Confirm destructives

For delete operations, ask: "Type `yes delete <slug>` to confirm."
Match on the resource **slug** (not display name). Accept if the user's
response contains `yes delete` followed by the correct slug (case-insensitive).
Partial confirmations ("yes", "go ahead", "sure") are insufficient — re-prompt.

`alvera connected-apps sync-routes <datalake> <id>` mutates routing
state on the remote app. Confirm with a plain "y/n" before invoking.

## Secrets handling

Two categories:

1. **Login credentials** — used by `alvera login`, which the **user**
   runs themselves. Skill never collects the password, never invokes
   `login`.
2. **Resource secrets** — values inside tool bodies (AWS keys,
   assume-role ARNs, API tokens, etc.).

### Login credentials

- Skill **does not collect** the password and **does not invoke**
  `alvera login`.
- Never instruct the user to pass `--password` on the command line.
- If `alvera whoami` shows no token, expired, or wrong tenant, ask the
  user to re-run `login` for that profile.

### Session token

- Stored by the CLI in `~/.alvera-ai/credentials` (mode 0600).
- Never echo the token. Never write it to YAML. Never log it.
- On user "done" signal, suggest `alvera logout`.

### Resource secrets

- **Preferred**: accept an env var name (`"AWS_ACCESS_KEY_ID"`) and let
  the runtime resolve it.
- **Acceptable**: accept a one-shot literal value, write it into a
  tempfile JSON body, pass via `--body-file`, then delete the tempfile.
  Never inline a secret into `--body '<json>'`.

### Datalake DB credentials

Up to eight passwords + usernames (four DB roles × 2). Three sourcing
patterns — **actively ask, don't passively list**:

- **(a) Existing env vars** — user gives names, not values. Skill uses
  `envsubst` to expand into tempfile.
- **(b) Scaffold `./.alvera.datalake.env`** — skill writes variable
  names with empty values, appends filename to `./.gitignore`, user fills
  in, skill sources and uses. Recommended default for first-time setup.
- **(c) One-shot literals** — least preferred. Write to tempfile, run, rm.

When scaffolding `.alvera.datalake.env`:
- Values must be **empty quotes** (`VAR=""`), never `changeme`.
- Append filename to `./.gitignore` before telling user it's safe to fill.
- On source, verify every variable is non-empty; stop and name blanks.

Forbidden:
- Echoing a resolved secret value back to the user.
- Logging a resolved secret value.
- Writing a resolved secret value to the YAML receipt. Use `$ENV_NAME`
  if known, or `<set at runtime>` if literal.

## Dependency ordering

If a resource depends on another that doesn't exist yet, surface the gap
and offer to create the dependency first. Do not silently skip or invent
ids.

Common dependencies:
- `tools` with `data_source_id` → data source must exist
- `action-status-updaters.updater_tool_id` → tool must exist
- `ai-agents.tool_id` → tool must exist
- `workflows` → AI agents, tools, connected apps must exist
- `DACs` → tool + data source must exist
- `DACs` → interop contracts (deferred until after contract creation)

## Enum validation: the API is authoritative

Enum lists in `resources.md` are **hints for conversation flow**, not the
source of truth.

1. User supplies a value matching `resources.md` → use it.
2. User supplies something plausible but not in the documented list →
   pass it through to the CLI. The list may be stale.
3. On a 4xx, surface stderr verbatim, re-elicit just that field. Note the
   valid values from the error for subsequent prompts in this session.
4. If API contradicts `resources.md`, API wins.

Structural validations (required fields, valid cron, positive integers,
column count ≥ 1, snake_case names) stay client-side.

## Read-before-write for updates

Before `update`:
1. Fetch the current entity.
2. Show current values as plain-language summary.
3. Show proposed changes as `old → new` bullets.
4. Require explicit confirmation.

## Errors

CLI exits non-zero on any failure. Surface stderr verbatim.
Do not invent fallbacks. Do not retry without asking. Do not swallow.

**Recovery pattern:** When a command fails:
1. Show the error to the user verbatim.
2. Diagnose: is it a field validation error (4xx), auth issue, or server error?
3. Suggest a specific next step:
   - 4xx → "Field `X` was rejected. What value should I use instead?"
   - 401/403 → "Session may be expired. Please re-run `alvera login`."
   - 5xx → "Server error. Try `alvera raw GET <path>` to verify, or retry?"
   - Timeout → "Request timed out. Retry? (y/n)"
4. If the user says retry, re-run the exact same command once.
