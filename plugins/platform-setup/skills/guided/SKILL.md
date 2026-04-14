---
name: guided
description: >
  Conversationally provision Alvera platform resources (datalakes, data sources, tools,
  generic tables, action status updaters, AI agents, connected apps) on an existing
  tenant. A datalake is required for most resources — if the tenant has none, the skill
  will offer to create one first (DB credentials elicited conversationally; secrets
  handled via env vars or a `.env` file, never inlined). Use when the user wants to set
  up infrastructure on Alvera, "create a datalake", "create a data source", "add a tool",
  "wire up an AI agent", or similar. Drives the `alvera` CLI shipped by
  `@alvera-ai/platform-sdk` via `npx`. Auth is session-based — the user runs `alvera login`
  themselves once; the skill never sees the password. Never asks the user for a YAML file —
  elicits fields conversationally and emits an infra.yaml receipt. Do NOT use for tenant
  provisioning (admin-only) or for runtime ops like dataset search, workflow execution,
  or data activation ingest.
---

# Alvera Platform — Guided Setup

Conversationally provision Alvera platform resources for an existing
tenant + datalake. Conversation is the input; an `infra.yaml` receipt is
the output. The user never writes YAML — and never hands the skill their
password.

## Prerequisites (in order)

1. **`alvera` CLI reachable.** Either installed globally
   (`npm install -g @alvera-ai/platform-sdk` or `pnpm add -g ...`) or
   runnable via `npx -p @alvera-ai/platform-sdk alvera`. Verify this
   **first** — before asking the user any provisioning questions — by
   attempting `alvera --version` then `npx ... alvera --version`. If
   both fail, hand the user the install command and stop; do not try to
   install the CLI (or Node) yourself. Full procedure in
   `references/bootstrap.md` → "Step 0".
2. A valid session for the target tenant (the user runs `alvera login`
   themselves — see `references/bootstrap.md`).
3. **A datalake** — either an existing one, or one the skill creates at
   the start of the session. Most resources are datalake-scoped, so if
   the tenant has none, the first thing the skill does is offer to
   create one. Datalake creation requires DB credentials; treat them as
   secrets (env var names or a `.env` file, never inlined in shell
   args) — see `references/resources.md` → "Datalake" and
   `references/guardrails.md` → "Secrets handling".

## Workflow

1. **Resolve the `alvera` prefix** — `references/bootstrap.md` → "Step 0".
   Try `alvera --version`, then `npx -p @alvera-ai/platform-sdk alvera --version`.
   Pin whichever works. If both fail, hand the user
   `npm install -g @alvera-ai/platform-sdk` and stop.
2. **Bootstrap the session** — `references/bootstrap.md`. Confirm the
   user has run `alvera login` themselves; verify with `alvera whoami` +
   `alvera ping`; pick the target datalake via `alvera datalakes list`.
3. **Open the resource loop** — ask what the user wants to set up.
4. **Per resource:**
   - **List first** to detect collisions (`alvera <resource> list ...`).
   - **Elicit fields** per `references/resources.md`. Enum lists there are
     **hints to guide the conversation**, not authoritative — the CLI/API
     is the source of truth.
   - **Summarise in plain language** for explicit confirmation — a
     compact bulleted recap of the fields, not a JSON dump. Raw JSON
     belongs in the tempfile that goes to `--body-file`, not in chat.
     Example: "Creating data source **prime-emr-source** (uri
     `our-emr:prime-emr-source`, status active, not default). Proceed?"
     Only fall back to a JSON-ish form when the user explicitly asks
     ("show me the JSON", "show the full body").
   - **Call create** via the CLI (`references/cli-cheatsheet.md`). Treat
     any non-zero exit / 4xx as an authoritative validation failure:
     surface the stderr verbatim, map it back to the offending field, and
     re-elicit only that field. Do not retry the same payload.
   - **Append to `infra.yaml`** if the receipt is enabled
     (`references/yaml-receipt.md`) — only after a successful (2xx) create.
5. Loop until the user is done.

## Hard constraints

Read these before any user interaction:

- `references/scope.md` — what is in/out of scope, with refusal language.
- `references/guardrails.md` — non-negotiable rules: no silent upsert,
  destructive confirmations, secrets handling, dependency ordering,
  read-before-write for updates.

## CLI

This skill drives the `alvera` CLI shipped by
[`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk)
(>= 0.2.0). Two equivalent invocation forms — pick one and stay
consistent in the conversation:

```bash
# Zero-install (preferred — no project pollution)
npx -p @alvera-ai/platform-sdk alvera <command>

# Or install globally once
npm install -g @alvera-ai/platform-sdk
alvera <command>
```

All examples in the references use the bare `alvera <command>` form for
readability. Substitute the `npx -p ...` prefix at run time.

The CLI exits non-zero on any API error. Surface stderr verbatim — no
fallbacks, no swallowing. Output is pretty JSON on stdout; status
messages and prompts go to stderr, so responses stay pipeable.

Auth is **session-based** and stored AWS-CLI-style under `~/.alvera-ai/`:

- `~/.alvera-ai/config` — base URL, default tenant, email per profile
- `~/.alvera-ai/credentials` — session token + `expires_at` (mode 0600)

The user runs `alvera login` once in their own shell. The skill never
collects the password and never invokes `login` itself.

## References

- `references/scope.md` — allowed/refused operations
- `references/bootstrap.md` — first-turn questions and connectivity checks
- `references/guardrails.md` — non-negotiable rules
- `references/resources.md` — per-resource field elicitation rules
- `references/yaml-receipt.md` — emitted YAML schema and rules
- `references/cli-cheatsheet.md` — CLI command surface
- `references/example-transcript.md` — reference end-to-end conversation
