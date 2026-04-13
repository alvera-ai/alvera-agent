# Guardrails (non-negotiable)

## No silent upsert

Always `list` before `create`. If a name collides with an existing
resource, stop and ask:

> "A `<resource>` named `<name>` already exists (id `<id>`). Do you want
> to (a) update it, (b) pick a different name, or (c) skip?"

Never auto-update on collision. Never auto-rename.

## Confirm destructives

`alvera tools delete` and `alvera ai-agents delete` require the user to
type `yes delete <name>` *exactly*. Partial confirmations ("yes",
"go ahead", "sure") are insufficient — re-prompt.

## Secrets handling

Two categories of secret in this skill:

1. **Login credentials** (`email` + `password`) — used by `alvera login`,
   which the **user** runs themselves in their terminal.
2. **Resource secrets** — values inside tool bodies (AWS keys,
   assume-role ARNs, API tokens, etc.).

The session token is held in `~/.alvera-ai/credentials` (mode 0600) by
the CLI — not in this conversation, not in any process arg list.

### Login credentials

- The skill **does not collect** the password and **does not invoke**
  `alvera login`. Always direct the user to run `login` themselves.
- Never instruct the user to pass `--password` on the command line — it
  would land in shell history and become visible to the model. Let the
  CLI's hidden prompt handle it. Same rule for `ALVERA_PASSWORD`.
- If `alvera whoami` shows no token, expired, or wrong tenant, ask the
  user to re-run `login` for that profile. Do not retry on their behalf.

### Session token

- Stored by the CLI in `~/.alvera-ai/credentials` (mode 0600). The skill
  does not read or copy it.
- Never echo the token. Never write it to YAML. Never log it.
- On user "done" signal, suggest `alvera logout` to revoke immediately
  rather than waiting for `expiresAt`.

### Resource secrets

- **Preferred**: accept an env var name (`"AWS_ACCESS_KEY_ID"`) and let
  the runtime resolve it.
- **Acceptable**: accept a one-shot literal value at conversation time,
  write it into a tempfile JSON body, pass via `--body-file`, then
  delete the tempfile. Never inline a secret into `--body '<json>'` —
  shell history would capture it.

Forbidden:
- Echoing a resolved secret value back to the user.
- Logging a resolved secret value.
- Writing a resolved secret value to the YAML receipt. In the YAML, write
  `$ENV_NAME` if known, or `<set at runtime>` if literal.

## Dependency ordering

If a resource depends on another that doesn't exist yet, surface the gap
and offer to create the dependency first. Do not silently skip or invent
ids.

Common dependencies:
- `tools` with `data_source_id` → data source must exist
- `action-status-updaters.updater_tool_id` → tool must exist
- `action-status-updaters.sender_tool_ids` → all referenced tools must exist
- `ai-agents.tool_id` → tool must exist

## Enum validation at conversation time

Reject invalid enum values *before* invoking the CLI. See
`resources.md` for the exact enums per field. Do not roundtrip to the
API to discover the user's enum was wrong.

## Read-before-write for updates

Before `alvera data-sources update` / `tools update` /
`action-status-updaters update` / `ai-agents update`:

1. Fetch the current entity (`alvera <resource> get ...` or `list` +
   filter on the JSON output).
2. Show the user the current values.
3. Show the proposed diff.
4. Require explicit confirmation before invoking `update`.

## Errors

The CLI exits non-zero on any failure (auth, validation, network, non-2xx
response). Surface stderr verbatim to the user. Do not invent fallbacks.
Do not retry without asking. Do not swallow.
