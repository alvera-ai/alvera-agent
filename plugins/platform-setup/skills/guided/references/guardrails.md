# Guardrails (non-negotiable)

## No silent upsert

Always `list` before `create`. If a name collides with an existing
resource, stop and ask:

> "A `<resource>` named `<name>` already exists (id `<id>`). Do you want
> to (a) update it, (b) pick a different name, or (c) skip?"

Never auto-update on collision. Never auto-rename.

## Confirm destructives

`tools.delete` and `aiAgents.delete` require the user to type
`yes delete <name>` *exactly*. Partial confirmations ("yes", "go ahead",
"sure") are insufficient — re-prompt.

## Secrets handling

Three categories of secret in this skill:

1. **Login credentials** (`email` + `password`) — collected at bootstrap
   to call `createSession`.
2. **Session token** — returned by `createSession`, used as the Bearer
   token for the `api` client.
3. **Resource secrets** — values inside tool bodies (AWS keys,
   assume-role ARNs, API tokens, etc.).

### Login credentials

- Use only to call `createSession`.
- Discard `email` and `password` from memory immediately after the call
  returns. Do not retain.
- Never echo, log, or write to disk.
- If `createSession` returns 401, ask the user to re-enter — do not retry
  with the same values.

### Session token

- Hold in process memory only, attached to the `api` client.
- Never write to YAML, never log, never echo back.
- On user "done" signal, call `revokeSession()` to invalidate immediately.

### Resource secrets

- **Preferred**: accept an env var name (`"AWS_ACCESS_KEY_ID"`) and
  resolve at runtime.
- **Acceptable**: accept a one-shot literal value, pass it through to the
  API, and immediately discard.

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
- `actionStatusUpdaters.updater_tool_id` → tool must exist
- `actionStatusUpdaters.sender_tool_ids` → all referenced tools must exist
- `aiAgents.tool_id` → tool must exist

## Enum validation at conversation time

Reject invalid enum values *before* calling the API. See
`resources.md` for the exact enums per field. Do not roundtrip to the
API to discover the user's enum was wrong.

## Read-before-write for updates

Before `dataSources.update` / `tools.update` / `actionStatusUpdaters.update` /
`aiAgents.update`:

1. Fetch the current entity (`get` or `list` + filter).
2. Show the user the current values.
3. Show the proposed diff.
4. Require explicit confirmation before calling `update`.

## Errors

All SDK methods throw on non-2xx. Catch the error and surface its message
verbatim to the user. Do not invent fallbacks. Do not retry without
asking. Do not swallow.
