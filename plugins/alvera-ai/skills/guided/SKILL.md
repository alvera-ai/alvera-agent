---
name: guided
description: >
  Outcome-driven Alvera platform provisioning. The user describes a business
  goal ("send review SMS after appointments", "onboard patient data from CSV",
  "create an AI agent for claim triage") and the skill derives the full
  dependency chain, checks what already exists, and provisions everything in
  the correct order — bottom-up execution, top-down design. Handles all
  resource types: datalakes, data sources, tools, generic tables (with
  compliance gate and column profiling), AI agents, agentic workflows (with
  templates and dry-run testing), connected apps, interop contracts, data
  activation clients, file ingestion (anti-pattern detection, Liquid template
  generation, sandbox testing), and PostgREST explorer scaffolding. Drives
  the `alvera` CLI from `@alvera-ai/platform-sdk`. Auth is session-based —
  the user runs `alvera login` themselves. Emits an `infra.yaml` receipt.
  Use when the user says anything about setting up, provisioning, onboarding,
  creating, or configuring Alvera platform resources.
---

# Alvera AI — Guided Setup

Outcome-driven provisioning. The user describes what they want to achieve;
the skill derives what's needed, checks what exists, and builds in order.

**Top-down design, bottom-up execution:**
- User: "I want to send review SMS after appointments"
- Skill: derives → workflow → SMS tool → data source → datalake
- Skill: checks → datalake exists, data source exists, tool missing, workflow missing
- Skill: provisions in order → tool → workflow → done

## Prerequisites (in order)

1. **`alvera` CLI reachable** — `alvera --version` or
   `npx -p @alvera-ai/platform-sdk alvera --version`. If both fail, hand
   the user `npm install -g @alvera-ai/platform-sdk` and stop.
   See `references/cli-cheatsheet.md`.
2. **Active session** — user runs `alvera login` themselves. Skill never
   collects passwords. Verify with `alvera whoami`.
3. **A datalake** — most resources are datalake-scoped. Offer to create if
   none exists.

## Workflow

### Step 1: Bootstrap

Resolve CLI prefix, authenticate, connectivity check, pick datalake.

Ask in a single prompt:
1. Profile name (default `default`)
2. Tenant slug
3. Base URL (default `https://admin.alvera.ai`)
4. Emit `infra.yaml` receipt? (default yes)

Verify session (`alvera whoami`), connectivity (`alvera ping`), pick datalake
(`alvera datalakes list`). If no datalake exists, offer to create one:

1. **Provision Postgres via Neon** — use the Neon API to create a project
   and get connection details in a single call. See
   `references/neon-project.md` for the full API surface, response shape,
   and mapping to Alvera datalake DB role fields. Requires `NEON_API_KEY`
   env var. This is the preferred path — one API call returns host, port,
   database, role, and password.
2. **Create the datalake on Alvera** — pass the Neon connection details
   into `alvera datalakes create` per `references/resources.md` → Datalake.
   All four Alvera roles (regulated/unregulated × reader/writer) can reuse
   the same Neon connection unless the user needs isolation.

Session state to retain: `profile`, `tenantSlug`, `datalakeSlug`,
`datalakeId`, `baseUrl`, receipt enabled, receipt path.

### Step 2: Outcome elicitation

Ask the user what they want to achieve — not what resource to create.

> "What are you trying to set up? Describe the goal — e.g.
> 'send review SMS after appointments', 'onboard patient data from a CSV',
> 'create an AI agent for triage', 'build an appointment reminder workflow',
> 'push data from a file'. Or name a specific resource if you know what you need."

Match the outcome to a dependency chain using `references/outcomes.md`.

If the outcome maps to a known chain, derive the plan. If the user names a
specific resource directly, treat it as a single-resource outcome (minimal
chain). If the outcome is ambiguous, ask one clarifying question and proceed.

### Step 3: Gap analysis

For each resource in the derived chain, check if it already exists:

```bash
alvera --profile <p> <resource> list ...   # per resource type
```

Present the gap analysis:

> "To achieve **review SMS after appointments**, I need:
>   ✓ Datalake `acme-health` — exists
>   ✓ Data source `appointments` — exists
>   ✗ SMS tool — missing
>   ✗ Review workflow — missing
>
> I'll create the missing resources in this order:
>   1. SMS tool (depends on: data source ✓)
>   2. Review workflow (depends on: SMS tool, data source ✓)
>
> Proceed? (y/n)"

When everything already exists, tell the user and ask if they want to
create something additional or adjust.

### Step 4: Execute plan

Provision resources in dependency order. For each:

1. **List** existing to detect collisions (guardrails: no silent upsert).
2. **Elicit** missing fields per `references/resources.md`.
3. **Confirm** in plain language (bullets, not JSON).
4. **Create** via CLI (`references/cli-cheatsheet.md`).
5. **Append** to `infra.yaml` if receipt enabled (`references/yaml-receipt.md`).
6. **Move** to next resource in the chain.

Complex sub-flows handled inline:

- **Data pipeline** (file → table → upload): follow `references/data-pipeline.md`
  for compliance gate, column profiling, table creation, anti-pattern scan,
  interop template generation, sandbox test, and upload.
- **Workflow creation** (template or custom): follow `references/workflows.md`
  for template selection, custom build, draft creation, dry-run test, log
  interpretation, and promotion to live.
- **Query scaffold**: follow `references/query.md` for PostgREST explorer.

After the chain is complete, report what was created.

### Step 5: Loop

> "Done — review SMS workflow is live. What else do you want to achieve?"

Continue until the user says done. On done, suggest `alvera logout`.

## Stance: be proactive

Assume forward progress. Default to the positive action, confirm with y/n.
Don't present long menus when one path is obvious.

- Resolve everything possible before asking.
- When only one option exists, use it and tell the user.
- Anti-pattern scans and sandbox tests run automatically.
- When the user agrees, move immediately — don't re-confirm.

## Hard constraints

Read before any user interaction:

- `references/scope.md` — what is in/out of scope, with refusal language.
- `references/guardrails.md` — non-negotiable rules: no silent upsert,
  destructive confirmations, secrets handling, dependency ordering,
  read-before-write for updates.

## CLI

`alvera` from [`@alvera-ai/platform-sdk`](https://www.npmjs.com/package/@alvera-ai/platform-sdk)
(>= 0.2.0). Two invocation forms:

```bash
npx -p @alvera-ai/platform-sdk alvera <command>   # zero-install
alvera <command>                                    # if installed globally
```

Auth is session-based, stored AWS-CLI-style under `~/.alvera-ai/`.
User runs `alvera login` in their own shell. Skill never sees the password.

## References

- `references/outcomes.md` — outcome → dependency chain catalog
- `references/resources.md` — per-resource field elicitation rules
- `references/guardrails.md` — non-negotiable rules
- `references/scope.md` — allowed/refused operations
- `references/cli-cheatsheet.md` — CLI command surface
- `references/data-pipeline.md` — file → table → template → upload flow
- `references/workflows.md` — workflow templates, liquid variables, execution
- `references/query.md` — PostgREST explorer scaffold templates
- `references/yaml-receipt.md` — emitted YAML schema and rules
- `references/neon-project.md` — Neon API for Postgres provisioning (datalake DB backend)
- `references/example-transcript.md` — reference end-to-end conversations
