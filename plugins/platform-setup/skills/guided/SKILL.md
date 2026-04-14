---
name: guided
description: >
  Conversationally provision Alvera platform resources (data sources, tools, generic tables,
  action status updaters, AI agents, connected apps) for a tenant that already has at least one datalake
  provisioned. **A datalake is the first hard requirement** — without it, nothing in this
  skill can run; the user must ask their Alvera admin to provision one first. Use when the
  user wants to set up infrastructure on Alvera, "create a data source", "add a tool",
  "wire up an AI agent", or similar. Drives the `alvera` CLI shipped by
  `@alvera-ai/platform-sdk` via `npx`. Auth is session-based — the user runs `alvera login`
  themselves once; the skill never sees the password. Never asks the user for a YAML file —
  elicits fields conversationally and emits an infra.yaml receipt. Do NOT use for tenant or
  datalake provisioning (admin-only) or for runtime ops like dataset search or workflow
  execution.
---

# Alvera Platform — Guided Setup

Conversationally provision Alvera platform resources for an existing
tenant + datalake. Conversation is the input; an `infra.yaml` receipt is
the output. The user never writes YAML — and never hands the skill their
password.

## Prerequisites (in order)

1. **Host toolchain reachable.** Node ≥ 20, plus either the `alvera` CLI
   installed globally *or* a working `npx` (so we can run
   `npx -p @alvera-ai/platform-sdk alvera ...`). Check **this first** —
   before asking the user any provisioning questions — and report all
   missing pieces at once. Do not attempt to install Node / npm / pnpm /
   the CLI for the user; refuse and hand them the install hint. Full
   preflight procedure in `references/bootstrap.md` → "Step 0".
2. **A provisioned datalake on the target tenant.** Non-negotiable —
   every resource this skill creates is scoped to a datalake. If the
   tenant has none, the skill cannot proceed; tell the user to ask their
   Alvera admin to provision one, then come back. Datalake creation is
   admin-only and out of scope.
3. A valid session for the target tenant (the user runs `alvera login`
   themselves — see `references/bootstrap.md`).

## Workflow

1. **Toolchain preflight** — `references/bootstrap.md` → "Step 0". Verify
   `node --version` (≥ 20) and resolve the `alvera` invocation prefix
   (global binary vs `npx`). Refuse with install hints if anything is
   missing.
2. **Bootstrap the session** — `references/bootstrap.md`. Confirm the
   user has run `alvera login` themselves; verify with `alvera whoami` +
   `alvera ping`; pick the target datalake via `alvera datalakes list`.
3. **Open the resource loop** — ask what the user wants to set up.
4. **Per resource:**
   - **List first** to detect collisions (`alvera <resource> list ...`).
   - **Elicit fields** per `references/resources.md`. Enum lists there are
     **hints to guide the conversation**, not authoritative — the CLI/API
     is the source of truth.
   - **Echo the JSON body** for explicit confirmation.
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
